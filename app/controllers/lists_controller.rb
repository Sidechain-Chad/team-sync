class ListsController < ApplicationController
  before_action :authenticate_user!

  def create
    @board = current_user.all_boards.find(params[:board_id])
    @list = @board.lists.new(list_params)

    if @list.save
      # Insertion is broadcast (see broadcast_list_insert), not rendered into
      # this response — the actor is subscribed to the same board stream, so
      # rendering it here too would double it up. Only the form reset below
      # is actor-only. Same convention as CardsController#create.
      broadcast_list_insert(@list)

      respond_to do |format|
        format.turbo_stream do
          # Replace the form with a fresh, empty copy (this clears the input)
          render turbo_stream: turbo_stream.replace("new_list_form", partial: "boards/new_list_form", locals: { board: @board })
        end

        format.html { redirect_to board_path(@board) }
      end
    else
      redirect_to board_path(@board), alert: "Could not create list"
    end
  end

  def edit
    @list = current_user.all_lists.find(params[:id])
  end

  def update
    @list = current_user.all_lists.find(params[:id])
    if @list.update(list_params)
      # A rename or a WIP-limit change was previously invisible to other viewers
      # until they reloaded. Broadcast the SAME header frame the actor's own
      # response replaces below, rather than inventing a second targeting
      # scheme — the frame already exists on every viewer's board page.
      #
      # No anti-double-render dance needed here (unlike broadcast_card_insert):
      # `replace` targets by id and is idempotent, so the actor receiving both
      # their own response and this broadcast just replaces the same frame
      # twice. Only append/before can duplicate content.
      #
      # Two accepted side effects for OTHER viewers, both fine for an action
      # this rare: the ... dropdown lives inside this frame, so an open menu on
      # this list closes; and the frame holds the board-filter listCount target
      # ("3 of 7"), so an active filter's count blanks until they re-filter.
      broadcast_header_replace(@list)

      respond_to do |format|
        format.html { redirect_to board_path(@list.board) }

        # FIX: Now we simply replace the header partial!
        format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(@list, :header), partial: "lists/header", locals: { list: @list }) }
      end
    else
      # `render :edit` on its own resolved the template against the REQUEST's
      # formats, and lists/edit exists only as HTML — so a turbo-stream-only
      # Accept raised MissingTemplate: a 500 on an ordinary validation failure
      # (blank rename, or a WIP limit of 0). Both formats are explicit now.
      error = @list.errors.full_messages.to_sentence

      respond_to do |format|
        # Re-render the inline rename form so the user can correct it. 422 —
        # Turbo needs a 4xx to re-render a form.
        format.html { render :edit, formats: [:html], status: :unprocessable_entity }

        # Deliberately 200, not 422: both entry points (the inline rename form
        # and the WIP-limit form in the ⋯ menu) submit from INSIDE the list
        # header frame, and Turbo does not apply a turbo-stream response to a
        # frame-targeted submission when the status is 4xx — the body would be
        # correct and the user would see nothing at all. Same 200 + flash.now
        # shape CardsController#update already uses for its rejected update.
        format.turbo_stream do
          flash.now[:alert] = error
          # Re-read so the header renders the list as it actually stands: the
          # rejected value is discarded, never left half-applied on screen.
          @list.reload

          render turbo_stream: [
            turbo_stream.replace(
              helpers.dom_id(@list, :header),
              partial: "lists/header",
              locals: { list: @list }
            ),
            # The header frame doesn't contain the flash slot, so without this
            # the alert would never be seen. shared/_flash exists for exactly
            # this (see its own comment) — this is its first caller.
            turbo_stream.replace("flash", partial: "shared/flash")
          ]
        end
      end
    end
  end

  def destroy
    @list = current_user.all_lists.find(params[:id])
    @list.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@list) }
      format.html { redirect_to board_path(@list.board) }
    end
  end

  def move
    @list = current_user.all_lists.find(params[:id])
    @list.insert_at(list_params[:position].to_i)

    # Broadcast new ordering to everyone viewing the board so other
    # users see the reorder without a refresh. Every list re-renders every
    # one of its cards (lists/list -> cards/card), so this needs the same
    # eager-loading as boards#show or it's an N+1 across the whole board.
    board = @list.board
    lists = board.lists.includes(active_cards: Card::BOARD_PAGE_INCLUDES)
    lists.each do |list|
      Turbo::StreamsChannel.broadcast_replace_to(
        board,
        target: helpers.dom_id(list),
        partial: "lists/list",
        locals: { list: list }
      )
    end

    head :ok
  end

  # "Archive all cards" (list ⋯ menu). Archives every ACTIVE card in the list
  # and logs an archived activity per card — consistent with single-card
  # archive, and honest history even though it can be many entries at once.
  def archive_all_cards
    @list = current_user.all_lists.find(params[:id])

    @list.active_cards.each do |card|
      card.archive!
      card.log_activity(current_user, "archived")
    end

    # One full list replace rather than N individual removes: the header's
    # card count changes too, and a single replace is the same thing
    # CardsController#create's gap-insert branch broadcasts for a multi-card
    # change. Broadcast-only — the actor is subscribed to this stream.
    broadcast_list_replace(@list)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to board_path(@list.board) }
    end
  end

  # "Copy list" (list ⋯ menu). Duplicates the list and its active cards onto the
  # SAME board — see List#copy_to for what does and doesn't come across.
  #
  # Same board only, so no label remapping is needed here (labels belong to the
  # board, and the copy stays on it). Cross-board list copy would need board
  # copy's label_map machinery and is deliberately not offered.
  def copy
    @list = current_user.all_lists.find(params[:id])

    begin
      new_list = @list.copy_to(board: @list.board, name: params[:name], user: current_user)
    rescue ActiveRecord::RecordInvalid => e
      # copy_to's transaction already rolled back — nothing was persisted. Same
      # shape as CardsController#copy's failure branch: back to a real page with a
      # flash, not a raw 500.
      return redirect_to board_path(@list.board),
                         alert: "Couldn't copy this list: #{e.record.errors.full_messages.to_sentence}"
    end

    # ONE broadcast, not one per card: lists/_list renders its own cards, so the
    # whole populated column arrives in a single insert. Broadcast-only — the
    # actor is subscribed to this board's stream too, so rendering the list in
    # this response as well would insert it twice (the same convention #create
    # and CardsController#create follow).
    #
    # Inserted AFTER the source, matching where List#copy_to just positioned it.
    #
    # Re-read with BOARD_PAGE_INCLUDES first. #create broadcasts a brand-new
    # (therefore empty) list and needs no preload, but a COPY arrives full of
    # cards, and rendering lists/_list without the preload is an N+1 across every
    # one of them. Same preload broadcast_list_replace uses.
    broadcast_list_insert_after(list_with_cards_preloaded(new_list), after: @list)

    respond_to do |format|
      # The response used to be `head :ok`. "Render nothing for the LIST" (correct —
      # the broadcast delivers it, and rendering it here too would insert it twice)
      # had been over-applied into "render nothing at all", so submitting the form
      # produced no flash, left the dropdown open still showing the typed name, and
      # looked exactly like nothing had happened. The name was always being applied;
      # this is purely the missing confirmation.
      #
      # Still NO list markup here — only the flash slot, which is a different
      # target, so the one-broadcast / no-double-render property is untouched.
      # notice rather than alert so it inherits shared/_flash's 5-second
      # auto-dismiss; errors are the ones that persist.
      format.turbo_stream do
        flash.now[:notice] = "List copied as \"#{new_list.name}\"."
        render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
      end

      format.html { redirect_to board_path(@list.board), notice: "List copied as \"#{new_list.name}\"." }
    end
  end

  # "Sort by" (list ⋯ menu). Persists the new order by renumbering positions
  # (see List#sort_cards!) — a one-time reorder, not a sticky sort mode.
  def sort
    @list = current_user.all_lists.find(params[:id])

    return head :unprocessable_entity unless @list.sort_cards!(params[:sort])

    broadcast_list_replace(@list)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to board_path(@list.board) }
    end
  end

  private

  # Replaces just the list's header frame for every viewer of the board — the
  # rename link, the filtered-count target, the WIP pill and the ... menu. Not
  # the whole list column: #update never changes which cards are in the list, so
  # re-rendering every card would be pure waste (and an N+1 without a preload).
  def broadcast_header_replace(list)
    Turbo::StreamsChannel.broadcast_replace_to(
      list.board,
      target: helpers.dom_id(list, :header),
      partial: "lists/header",
      locals: { list: list }
    )
  end

  # Re-renders the whole list column for every viewer of the board. Needs the
  # same eager-loading as boards#show — the partial renders every one of the
  # list's cards (lists/list -> cards/card), so without it this is an N+1
  # across the list. Same reasoning as #move's per-list broadcast.
  def broadcast_list_replace(list)
    Turbo::StreamsChannel.broadcast_replace_to(
      list.board,
      target: helpers.dom_id(list),
      partial: "lists/list",
      locals: { list: list_with_cards_preloaded(list) }
    )
  end

  # Re-reads a list with everything lists/_list needs to render every one of its
  # cards. Mandatory before broadcasting a list that HAS cards — without it,
  # rendering the column is an N+1 across the list. #create's brand-new list is
  # empty so it doesn't need this; #copy's very much does.
  def list_with_cards_preloaded(list)
    current_user.all_lists
                .includes(active_cards: Card::BOARD_PAGE_INCLUDES)
                .find(list.id)
  end

  # Mirror of CardsController#broadcast_card_insert, one level up: a list
  # created by one member should appear live for everyone else on the board.
  #
  # Targets "new_list_form" (the "+ Add another list" column), not the
  # #board_lists container: the add-list column and the "Archived items" link
  # are both siblings of the list columns INSIDE #board_lists (see
  # boards/show.html.erb), so appending to the container would land the new
  # list after those affordances instead of before them.
  def broadcast_list_insert(list)
    Turbo::StreamsChannel.broadcast_before_to(
      list.board,
      target: "new_list_form",
      partial: "lists/list",
      locals: { list: list }
    )
  end

  # #copy's insert, which must land the new column in the SAME place the DB now
  # says it is: immediately after the source. broadcast_list_insert always targets
  # `before: new_list_form`, i.e. the far right end of the board — correct for
  # #create (a new list does belong at the end) but wrong here, and wrong in a
  # particularly misleading way: the row order in the database was right, so a
  # reload showed the copy in the right place while every live viewer, the actor
  # included, watched it appear off-screen at the end. Caught in the browser, not
  # by the position test.
  #
  # `after` the source rather than `before` the following list: the source is a
  # stable target that always exists, whereas "the list that now follows" may be
  # nothing at all when the source was last.
  def broadcast_list_insert_after(list, after:)
    Turbo::StreamsChannel.broadcast_after_to(
      list.board,
      target: helpers.dom_id(after),
      partial: "lists/list",
      locals: { list: list }
    )
  end

  def list_params
    params.require(:list).permit(:name, :position, :card_limit)
  end
end
