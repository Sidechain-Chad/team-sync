class CardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card, only: [:show, :edit, :update, :destroy, :move, :copy, :edit_description, :update_description, :archive, :unarchive, :toggle_complete]

  def show
    # Eager-load everything the card modal needs
    @card = current_user.all_cards
                        .includes(
                          :labels,
                          { members: { avatar_attachment: :blob } },
                          { list: { board: [:labels, { members: { avatar_attachment: :blob } }, { user: { avatar_attachment: :blob } }] } },
                          { checklists: :checklist_items },
                          { comments: { user: { avatar_attachment: :blob } } },
                          { activities: { user: { avatar_attachment: :blob } } }
                        )
                        .find(params[:id])

    @feed = (@card.comments + @card.activities).sort_by(&:created_at).reverse
    resolve_return_to!
  end

  def edit
  end

  def new
    @list = current_user.all_lists.find(params[:list_id])
    @card = @list.cards.build
  end

  def create
    @list = current_user.all_lists.find(params[:list_id])
    # The gap inserter (gap_insert_controller.js) submits an explicit
    # position — the position of the card that ends up BELOW the new one.
    # Pulled out before building so acts_as_list's normal "add to bottom"
    # create callback runs first; inserting mid-list is then a follow-up
    # #insert_at, same as any other card move.
    requested_position = card_params[:position]
    @card = @list.cards.build(card_params.except(:position))

    if @card.save
      @card.log_activity(current_user, "created", @list.name)

      if requested_position.present?
        @card.insert_at(resolved_move_position(requested_position, @list))

        # Unlike the bottom "Add a card" flow (which only needs to append
        # for the requester), a mid-list insert shifts every card below it —
        # their data-position attributes are now stale for anyone else
        # looking at this list. Broadcasting a full list replace (the same
        # partial ListsController#move already broadcasts for reordering)
        # refreshes every viewer, including this client, since boards/show
        # subscribes to the board's stream too — so the HTTP response
        # itself has nothing left to render.
        broadcast_list_replace(@list)

        respond_to do |format|
          format.turbo_stream { head :ok }
          format.html { redirect_to @list.board }
        end
      else
        # Insertion is broadcast (see broadcast_card_insert), not rendered
        # into this response — the actor is subscribed to the same board
        # stream, so rendering it here too would double it up. The
        # turbo_stream response (cards/create.turbo_stream.erb) only resets
        # the "Add a card" trigger, which IS actor-only.
        broadcast_card_insert(@card)
        # The gap-insert branch above doesn't need this — its full list replace
        # already re-renders the pill.
        broadcast_list_card_count(@list)

        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to @list.board }
        end
      end
    else
      redirect_to @list.board, alert: "Title cannot be blank."
    end
  end

  def update
    # Guard against no-op location PATCHes — if all four location fields
    # arrive blank AND the card already has no location, there's nothing
    # to do. Prevents stray clicks from triggering pointless writes.
    if location_only_blank_patch?
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html         { redirect_to @card.list.board }
      end
      return
    end

    # list_id can be mass-assigned here (see card_params) to support moving
    # a card via the modal, but it must be resolved through the user's scope
    # and confined to the card's current board — same reasoning as #move.
    target_list = nil
    if params.dig(:card, :list_id).present?
      target_list = board_scoped_list(params[:card][:list_id])
      return head :unprocessable_entity unless target_list
    end

    old_list = @card.list

    # Detect new attachments BEFORE the update fires. We pass these to the
    # service for validation/attaching, and use the count to decide which
    # turbo_stream response to send back (full modal vs. just the due pill).
    new_attachments = Array(params.dig(:card, :attachments)).reject(&:blank?)

    # The "Move to list" control (card modal, Actions section) submits a
    # semantic top/bottom choice rather than a raw position — resolving it
    # here (against the actual target list, not whatever list was current
    # when the form was rendered) avoids the value going stale if the user
    # picks a different list than the one the position select was drawn for.
    update_attrs = card_params.except(:attachments)
    if target_list && params.dig(:card, :position).present?
      update_attrs = update_attrs.merge(position: resolved_move_position(params[:card][:position], target_list))
    end

    if @card.update(update_attrs)
      if @card.list_id != old_list.id
        @card.log_activity(current_user, "moved", "#{old_list.name} to #{@card.list.name}")
      elsif @card.saved_change_to_due_date?
        if @card.due_date.present?
          @card.log_activity(current_user, "set_due_date", @card.due_date.strftime("%b %-d"))
        else
          @card.log_activity(current_user, "removed_due_date")
        end
      elsif @card.saved_change_to_completed?
        @card.log_activity(current_user, @card.completed? ? "completed_card" : "uncompleted_card")
      elsif @card.saved_change_to_title?
        @card.log_activity(current_user, "renamed", @card.title)
      end

      # Use the service for attachments — handles validation (size + type)
      # and logs one activity entry per file.
      result = CardAttachmentService.new(card: @card, user: current_user, files: new_attachments).call

      if @card.list_id != old_list.id
        # The modal's "Move to list" control moves a card through #update, not
        # #move. A bare card replace is actively wrong here, not merely
        # incomplete: it targets the card's own dom_id, so other viewers
        # re-render it in place in the OLD list and it never appears to move.
        # Two full list replaces relocate it properly and refresh both headers
        # (count pills included), so no separate pill broadcast is needed.
        broadcast_list_replace_for(old_list, @card.list)
      else
        # Broadcast the freshly-rendered card to anyone viewing this board so
        # the preview reflects changes (location pin, attachment count, due
        # pill, title) in real time. Same pattern as toggle_complete. This is
        # the common edit path — one card replace, exactly as before.
        Turbo::StreamsChannel.broadcast_replace_to(
          @card.list.board,
          target: @card,
          partial: "cards/card",
          locals: { card: @card }
        )
      end

      if result.success?
        # Decide what to send back. Modal-wide refresh is needed when
        # something *visible inside the modal body* changed — attachments,
        # location, or the list (the header's list-name pill and the
        # activity feed both need to reflect a move). Otherwise the cheap
        # due-pill stream is enough.
        modal_refresh_needed = new_attachments.any? ||
          @card.saved_change_to_latitude? ||
          @card.saved_change_to_longitude? ||
          @card.saved_change_to_location_name? ||
          @card.saved_change_to_list_id?

        respond_to do |format|
          format.turbo_stream do
            if modal_refresh_needed
              # Re-eager-load so the cards/show template renders with fresh
              # attachments + activity entries. Replace the modal frame's
              # contents directly — no redirect, no top-level navigation,
              # no "Content missing" frame mismatch.
              reload_card_for_modal!
              render turbo_stream: turbo_stream.replace("modal", template: "cards/show")
            else
              render turbo_stream: turbo_stream.replace(
                "card_due_pill_#{@card.id}",
                partial: "cards/due_pill_frame",
                locals: { card: @card }
              )
            end
          end
          format.html { redirect_to @card.list.board }
        end
      else
        # Service rejected the upload (file too big, type not allowed).
        # Set flash.now and re-render the modal — the inline alert slot
        # in cards/show.html.erb picks the message up and renders it
        # next to the Attachment button. Re-rendering the modal also
        # keeps the dialog open so the user can immediately try again.
        respond_to do |format|
          format.turbo_stream do
            flash.now[:alert] = result.error
            reload_card_for_modal!
            render turbo_stream: turbo_stream.replace("modal", template: "cards/show")
          end
          format.html { redirect_to @card.list.board, alert: result.error }
        end
      end
    else
      # Same shape as the attachment-rejection branch above: flash.now plus a
      # modal re-render, which cards/show.html.erb's inline alert slot picks up.
      # (There is no cards/edit template to render — this branch was previously
      # unreachable, since title-presence was the only validation and no form
      # can submit a blank title. The start_date/due_date check makes it real.)
      error = @card.errors.full_messages.to_sentence

      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = error
          # Re-reads from the DB, so the modal shows the card as it actually
          # stands — the rejected values are discarded, never half-applied.
          reload_card_for_modal!
          resolve_return_to!
          # Deliberately 200, not 422: the due-date form is frame-targeted
          # (data-turbo-frame="card_due_pill_X"), and Turbo does NOT apply a
          # turbo-stream response to a frame-scoped submission when the status
          # is 4xx — the error would be silently swallowed in the browser even
          # though the body is correct. Verified in-browser. Same 200 +
          # flash.now + modal-replace shape the attachment-rejection branch
          # above already uses for a rejected card update.
          render turbo_stream: turbo_stream.replace("modal", template: "cards/show")
        end
        format.html { redirect_to @card.list.board, alert: error }
      end
    end
  end

  def destroy
    @board = @card.list.board
    list = @card.list
    @card.destroy

    # Hard delete drops the list's active-card count too. (The card's own
    # removal still isn't broadcast from here — a pre-existing gap, unchanged.)
    broadcast_list_card_count(list)

    # If the request came from the archive page, return there.
    # Otherwise back to the board.
    if request.referer&.include?("/archive")
      redirect_to archive_board_path(@board), status: :see_other
    else
      redirect_to @board, status: :see_other
    end
  end

  def move
    # drag_controller.js PATCHes JSON with the position/list_id nested
    # under "card" (matching card_params' shape), not at the top level.
    target_list = board_scoped_list(move_params[:list_id])
    return head :unprocessable_entity unless target_list

    old_list = @card.list

    # Positions are 1-based; the JS (newDraggableIndex + 1) already
    # converts from Sortable's 0-based index, so the server trusts it
    # verbatim rather than adding another +1.
    if @card.update(list_id: target_list.id, position: move_params[:position].to_i)
      # Matches #update's activity logging for a list change — without
      # this, a drag-and-drop move was invisible in the activity feed
      # while the same move made via the "Move to list" menu was visible.
      if @card.saved_change_to_list_id?
        @card.log_activity(current_user, "moved", "#{old_list.name} to #{@card.list.name}")
      end

      # Make the drag live for everyone else. Before this, #move broadcast
      # nothing at all, so another viewer saw neither the card leaving its old
      # list nor arriving in the new one until they reloaded — and once the
      # count pill started broadcasting, a destination could read "3/3" over
      # only 2 visible cards. A full replace of both lists keeps the cards and
      # the count in agreement, and fixes within-list reordering (also
      # previously invisible) via the single deduped replace.
      #
      # The actor still just gets head :ok — their own DOM is already correct
      # from SortableJS's optimistic move, and they receive these same
      # broadcasts anyway as a subscriber to the board's stream.
      broadcast_list_replace_for(old_list, @card.list)

      head :ok
    else
      head :unprocessable_entity
    end
  end

  # "Copy card" (card modal ⋯ menu). Target list is resolved through the
  # same board-scoped lookup #move uses, so a tampered list_id can't copy a
  # card onto a board the user can't access. The actual duplication lives
  # in Card#copy_to so it's unit-testable on its own.
  def copy
    target_list = board_scoped_list(params[:list_id])
    return head :unprocessable_entity unless target_list

    begin
      new_card = @card.copy_to(list: target_list, title: params[:title], user: current_user)
    rescue ActiveRecord::RecordInvalid => e
      # copy_to's transaction already rolled back — nothing was persisted.
      # Same shape as #create's validation-failure redirect: back to a
      # real page with a flash, not a raw 500.
      return redirect_to @card, alert: "Couldn't copy this card: #{e.record.errors.full_messages.to_sentence}"
    end

    # Land on the copy, board still visible behind it (same as opening any
    # other card) — not a full-page redirect_to card_path, which leaves the
    # board's canvas replaced by an empty page. The new card's insertion
    # into its target list is broadcast (see broadcast_card_insert), not
    # rendered here — the copier is subscribed to that same board stream,
    # so rendering it in this response too would insert it twice. Only the
    # modal replace belongs in this response: it's actor-only (only the
    # copier should be looking at the new card's own modal).
    broadcast_card_insert(new_card)
    broadcast_list_card_count(target_list)

    @card = new_card
    reload_card_for_modal!
    resolve_return_to!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("modal", template: "cards/show")
      end
      format.html { redirect_to card_path(@card) }
    end
  end

  def edit_description
  end

  def update_description
    if @card.update(description: params[:card][:description])
      @card.log_activity(current_user, "edited_description")
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(@card, :description), partial: "cards/description", locals: { card: @card }) }
        format.html { redirect_to @card }
      end
    else
      # cards/edit_description exists only as HTML, so a bare `render
      # :edit_description` raised MissingTemplate for a turbo-stream-only
      # Accept. Reaching this branch at all takes a card whose PERSISTED row is
      # already invalid — description has no validation of its own, so the only
      # way to fail is a pre-existing start_date > due_date (update_column, a
      # data import, an older row). Rare, but a 500 either way.
      error = @card.errors.full_messages.to_sentence

      respond_to do |format|
        format.html { render :edit_description, formats: [:html], status: :unprocessable_entity }

        # Mirrors the success path above — same frame, same partial — plus the
        # error. 200 rather than 422 for the same reason as
        # CardsController#update's rejected branch: this form is frame-targeted
        # (cards/edit_description wraps itself in the card's description frame),
        # and Turbo drops a 4xx turbo-stream response for a frame-targeted
        # submission. Reverting to the read-only description is right here: the
        # thing that needs fixing is the card's dates, not the text just typed.
        format.turbo_stream do
          flash.now[:alert] = error
          @card.reload

          render turbo_stream: [
            turbo_stream.replace(
              helpers.dom_id(@card, :description),
              partial: "cards/description",
              locals: { card: @card }
            ),
            turbo_stream.replace("flash", partial: "shared/flash")
          ]
        end
      end
    end
  end

  def archive
    @card.archive!
    @card.log_activity(current_user, "archived")
    broadcast_card_remove
    broadcast_list_card_count(@card.list)

    respond_to do |format|
      format.html { redirect_to board_path(@card.list.board) }
    end
  end

  def toggle_complete
    @card.update!(completed: !@card.completed?)
    @card.log_activity(current_user, @card.completed? ? "completed_card" : "uncompleted_card")

    # true only when this toggle just landed on completed (never on
    # un-completing) — passed to every render path below so the pop
    # animation is a one-shot tied to this exact transition, not a
    # property of the completed state itself.
    just_completed = @card.completed?

    # Re-broadcast the card to all viewers of the board so the green check
    # appears (or disappears) on every connected client. Other connected
    # clients get the pop too (acceptable — they're seeing the state
    # change land in real time same as the actor). The actor themselves
    # only double-renders here when the toggle came from the board tile
    # itself (see the bare `else` below, which renders nothing else), so
    # this is still exactly one visible pop for the actor in every case.
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card, just_completed: just_completed }
    )

    # Same idea, per member's own "My Cards" stream (account/cards.html.erb)
    # rather than the board — a card's members aren't all necessarily
    # looking at its board, but anyone with it assigned sees its row
    # everywhere it's open (another tab, or the row behind an open modal).
    # `sort` can't be known per-recipient here (each viewer's own page load
    # picked its own sort param) — "due" is just the account page's own
    # default, only relevant to that row's NEXT toggle's html fallback.
    @card.members.each do |member|
      Turbo::StreamsChannel.broadcast_replace_to(
        member, :cards,
        target: helpers.dom_id(@card, :account_row),
        partial: "account/card_row",
        locals: { card: @card, sort: "due", just_completed: just_completed }
      )
    end

    respond_to do |format|
      format.turbo_stream do
        if params[:from_modal].present?
          # The board-tile toggle relies on the broadcast above (every
          # connected client, including this one, is subscribed via
          # turbo_stream_from @board) — nothing else to render. But this
          # same endpoint is also the modal's title-circle toggle, which
          # isn't on the board page at all; for that one, explicitly
          # refresh the modal frame so the completed state flips in
          # place instead of the request falling through to the html
          # redirect below (which would just empty the modal, since the
          # board page's turbo-frame "modal" placeholder is empty).
          reload_card_for_modal!
          resolve_return_to!
          render turbo_stream: turbo_stream.replace("modal", template: "cards/show", locals: { just_completed: just_completed })
        elsif params[:from_account].present?
          # The account Cards page toggle now relies entirely on the
          # per-member broadcast above (the actor is one of @card.members,
          # so their own row gets replaced by it same as everyone else's) —
          # rendering the row again here too would double the pop for the
          # actor (response + their own broadcast landing back on the same
          # target). Nothing left for this response to do.
          head :ok
        else
          head :no_content
        end
      end
      format.html do
        if params[:from_account].present?
          redirect_to account_cards_path(sort: params[:sort])
        else
          redirect_to board_path(@card.list.board)
        end
      end
    end
  end

  def unarchive
    @card.unarchive!
    # Place at the bottom of the (now active) cards in its original list.
    @card.insert_at(@card.list.active_cards.count)

    @card.log_activity(current_user, "unarchived")

    # Tell the board's stream to reinsert the card at the bottom of its list.
    # Uses the same helper as create/copy: appending to list_X_cards landed the
    # restored card BELOW the "Add a card" trigger and the gap-inserter overlay,
    # both of which live inside that container.
    broadcast_card_insert(@card)
    broadcast_list_card_count(@card.list)

    # If the request came from the archive page, return there so the
    # user can keep restoring cards. Otherwise back to the board.
    if request.referer&.include?("/archive")
      redirect_to archive_board_path(@card.list.board)
    else
      redirect_to @card.list.board
    end
  end

  private

  def set_card
    @card = current_user.all_cards.find(params[:id])
  end

  # Resolves list_id through the user's scope (raises RecordNotFound, which
  # renders 404, for a list the user can't access at all), then confines it
  # to the card's current board. The UI never offers cross-board moves; if
  # that's ever wanted, this is where you'd strip the card's board-scoped
  # label/member associations before allowing it.
  def board_scoped_list(list_id)
    target_list = current_user.all_lists.find(list_id)
    target_list.board_id == @card.list.board_id ? target_list : nil
  end

  def move_params
    params.require(:card).permit(:list_id, :position)
  end

  # Translates the "Move card" popover's position choice into a real
  # acts_as_list position, relative to the actual target list rather than
  # whatever list the position select happened to be rendered against.
  # Accepts "top"/"bottom" (Actions-menu heritage) as well as a plain
  # integer (the popover's numeric Position select) — either way the
  # result is clamped to 1..bottom_position, so a stale or tampered client
  # count can never push the card out of the list's real bounds.
  def resolved_move_position(position_param, target_list)
    return 1 if position_param == "top"
    return bottom_position(target_list) if position_param == "bottom"

    position_param.to_i.clamp(1, bottom_position(target_list))
  end

  # Counts every card in the list (not just active_cards) — acts_as_list's
  # position sequence isn't filtered by archived state, matching how drag
  # (cards#move) already treats position as a raw column value. If the
  # card is already in the target list, it's part of this count — the
  # true bottom is the count itself, not count + 1.
  def bottom_position(target_list)
    if @card.list_id == target_list.id
      target_list.cards.count
    else
      target_list.cards.count + 1
    end
  end

  # Re-eager-loads the card and rebuilds @feed so cards/show.html.erb has
  # everything it needs when re-rendered from update (success or failure).
  def reload_card_for_modal!
    @card = current_user.all_cards
                        .includes(
                          :labels,
                          { members: { avatar_attachment: :blob } },
                          { list: { board: [:labels, { members: { avatar_attachment: :blob } }, { user: { avatar_attachment: :blob } }] } },
                          { checklists: :checklist_items },
                          { comments: { user: { avatar_attachment: :blob } } },
                          { activities: { user: { avatar_attachment: :blob } } }
                        )
                        .find(@card.id)
    @feed = (@card.comments + @card.activities).sort_by(&:created_at).reverse
  end

  # Where the modal's close (✕) button and overlay-click should land —
  # normally the card's board, but the account Cards page opens the modal
  # over itself and needs its own close destination back. `return_to` is
  # a strict enum check (never a path/URL), and `sort` is whitelisted to
  # the two values the account page's own sort links produce — neither
  # value is ever reflected into a link/redirect verbatim, so this can't
  # become an open redirect no matter what a client sends.
  def resolve_return_to!
    @return_to_account = params[:return_to] == "account"
    @return_to_sort = %w[due updated].include?(params[:sort]) ? params[:sort] : "due"
  end

  def card_params
    params.require(:card).permit(
      :title, :description, :due_date, :start_date, :completed, :list_id, :position,
      :latitude, :longitude, :location_name, :location_address,
      attachments: []
    )
  end

  # True when the incoming PATCH is location-only AND every location
  # field is blank AND the card has no existing location. Catches the
  # case from the 12:59:20 logs where an empty location form somehow
  # submitted on a card that never had a location to begin with.
  def location_only_blank_patch?
    p = params[:card] || {}
    location_keys = %w[latitude longitude location_name location_address]
    only_location_keys = (p.keys - location_keys).empty?
    all_blank          = location_keys.all? { |k| p[k].blank? }
    only_location_keys && all_blank && ! @card.location?
  end

  def broadcast_card_remove
    Turbo::StreamsChannel.broadcast_remove_to(@card.list.board, target: @card)
  end

  # Mirror of broadcast_card_remove. Insertion is broadcast (not rendered into
  # the actor's response) so every viewer of the board — including the actor,
  # who is subscribed to the same stream — gets exactly one copy. See
  # #toggle_complete for the same actor-double-render reasoning.
  #
  # Targets "list_#{id}_new_card" (the "Add a card" trigger frame), not the
  # list_#{id}_cards container itself: the trigger lives INSIDE that
  # container (see lists/_list.html.erb), so appending to the container
  # would land the new card after the trigger (and after the gap-inserter
  # overlay), not before it. `before` is what create.turbo_stream.erb
  # already used for the actor-only render this replaces.
  def broadcast_card_insert(card)
    Turbo::StreamsChannel.broadcast_before_to(
      card.list.board,
      target: "list_#{card.list_id}_new_card",
      partial: "cards/card",
      locals: { card: card }
    )
  end

  # Card-count pill only — NOT the whole list header, which owns the rename
  # control, the delete button, and the ... dropdown's Stimulus state (replacing
  # it would tear those down and could slam an open menu shut mid-interaction).
  #
  # Called from every path that changes a list's active-card count, EXCEPT the
  # ones that already broadcast a full list replace (ListsController#sort,
  # #archive_all_cards, and #create's gap-insert branch) — those re-render the
  # pill as part of the list partial, so adding this would double up.
  #
  # The list is reloaded so active_cards.size reflects the change that just
  # happened rather than an association cached before it.
  def broadcast_list_card_count(list)
    list = list.reload

    Turbo::StreamsChannel.broadcast_replace_to(
      list.board,
      target: "list_#{list.id}_card_count",
      partial: "lists/card_count",
      locals: { list: list }
    )
  end

  # Full replace of a list column for everyone viewing its board.
  #
  # This is what makes moves live. Deliberately NOT broadcast_card_remove +
  # broadcast_card_insert: the insert targets `before` the "Add a card" trigger,
  # so it always lands at the BOTTOM, while a drag can drop a card anywhere
  # mid-list. lists/_list renders active_cards in position order, so a full
  # replace gets arbitrary drop positions right for free — and re-renders the
  # header, which carries list_X_card_count, so the count pill comes along.
  #
  # Keyed off `list.board` rather than one assumed board so each list is
  # published to its own board's stream. (Today source and destination always
  # share a board — board_scoped_list confines the target to
  # @card.list.board_id — so this is equivalent, not load-bearing. It stays
  # per-list so it can't silently become wrong if that guard ever loosens.)
  #
  # The includes are mandatory: rendering a whole list means rendering every
  # cards/_card in it, which without the preload is an N+1 across the list.
  # Same preload ListsController#broadcast_list_replace uses.
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

  # A move touches two lists — or one, when the card never left its list.
  # Dedupes so a same-list reorder broadcasts a single replace.
  def broadcast_list_replace_for(*lists)
    lists.compact.uniq(&:id).each { |list| broadcast_list_replace(list) }
  end
end
