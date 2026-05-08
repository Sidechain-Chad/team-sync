class CardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card, only: [:show, :edit, :update, :destroy, :move, :edit_description, :update_description, :archive, :unarchive, :toggle_complete]

  def show
    # Eager-load everything the card modal needs
    @card = current_user.all_cards
                        .includes(
                          :labels,
                          :members,
                          { list: { board: [:labels, :members, :user] } },
                          { checklists: :checklist_items },
                          { comments: :user },
                          { activities: :user }
                        )
                        .find(params[:id])

    @feed = (@card.comments + @card.activities).sort_by(&:created_at).reverse
  end

  def edit
  end

  def new
    @list = current_user.all_lists.find(params[:list_id])
    @card = @list.cards.build
  end

  def create
    @list = current_user.all_lists.find(params[:list_id])
    @card = @list.cards.build(card_params)

    if @card.save
      @card.log_activity(current_user, "created", @list.name)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @list.board }
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

    old_list = @card.list

    # Detect new attachments BEFORE the update fires. We pass these to the
    # service for validation/attaching, and use the count to decide which
    # turbo_stream response to send back (full modal vs. just the due pill).
    new_attachments = Array(params.dig(:card, :attachments)).reject(&:blank?)

    if @card.update(card_params.except(:attachments))
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

      # Broadcast the freshly-rendered card to anyone viewing this board so
      # the preview reflects changes (location pin, attachment count, due
      # pill, title) in real time. Same pattern as toggle_complete.
      Turbo::StreamsChannel.broadcast_replace_to(
        @card.list.board,
        target: @card,
        partial: "cards/card",
        locals: { card: @card }
      )

      if result.success?
        # Decide what to send back. Modal-wide refresh is needed when
        # something *visible inside the modal body* changed — attachments
        # or location. Otherwise the cheap due-pill stream is enough.
        modal_refresh_needed = new_attachments.any? ||
          @card.saved_change_to_latitude? ||
          @card.saved_change_to_longitude? ||
          @card.saved_change_to_location_name?

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
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @board = @card.list.board
    @card.destroy

    # If the request came from the archive page, return there.
    # Otherwise back to the board.
    if request.referer&.include?("/archive")
      redirect_to archive_board_path(@board), status: :see_other
    else
      redirect_to @board, status: :see_other
    end
  end

  def move
    @card.update(
      list_id: params[:list_id],
      position: params[:position].to_i + 1
    )
    head :ok
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
      render :edit_description, status: :unprocessable_entity
    end
  end

  def archive
    @card.archive!
    @card.log_activity(current_user, "archived")
    broadcast_card_remove

    respond_to do |format|
      format.html { redirect_to board_path(@card.list.board) }
    end
  end

  def toggle_complete
    @card.update!(completed: !@card.completed?)
    @card.log_activity(current_user, @card.completed? ? "completed_card" : "uncompleted_card")

    # Re-broadcast the card to all viewers of the board so the green check
    # appears (or disappears) on every connected client.
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )

    respond_to do |format|
      format.html { redirect_to board_path(@card.list.board) }
    end
  end

  def unarchive
    @card.unarchive!
    # Place at the bottom of the (now active) cards in its original list.
    @card.insert_at(@card.list.active_cards.count)

    @card.log_activity(current_user, "unarchived")

    # Tell the board's stream to reinsert the card at the bottom of its list.
    Turbo::StreamsChannel.broadcast_append_to(
      @card.list.board,
      target: "list_#{@card.list_id}_cards",
      partial: "cards/card",
      locals: { card: @card }
    )

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

  # Re-eager-loads the card and rebuilds @feed so cards/show.html.erb has
  # everything it needs when re-rendered from update (success or failure).
  def reload_card_for_modal!
    @card = current_user.all_cards
                        .includes(
                          :labels,
                          :members,
                          { list: { board: [:labels, :members, :user] } },
                          { checklists: :checklist_items },
                          { comments: :user },
                          { activities: :user }
                        )
                        .find(@card.id)
    @feed = (@card.comments + @card.activities).sort_by(&:created_at).reverse
  end

  def card_params
    params.require(:card).permit(
      :title, :description, :due_date, :completed, :list_id,
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
end
