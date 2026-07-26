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
      respond_to do |format|
        format.html { redirect_to board_path(@list.board) }

        # FIX: Now we simply replace the header partial!
        format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(@list, :header), partial: "lists/header", locals: { list: @list }) }
      end
    else
      # If validation fails, re-render the edit form (inline)
      render :edit, status: :unprocessable_entity
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

  # Re-renders the whole list column for every viewer of the board. Needs the
  # same eager-loading as boards#show — the partial renders every one of the
  # list's cards (lists/list -> cards/card), so without it this is an N+1
  # across the list. Same reasoning as #move's per-list broadcast.
  def broadcast_list_replace(list)
    list_for_broadcast = current_user.all_lists
                                     .includes(active_cards: Card::BOARD_PAGE_INCLUDES)
                                     .find(list.id)

    Turbo::StreamsChannel.broadcast_replace_to(
      list.board,
      target: helpers.dom_id(list),
      partial: "lists/list",
      locals: { list: list_for_broadcast }
    )
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

  def list_params
    params.require(:list).permit(:name, :position, :card_limit)
  end
end
