class ChecklistsController < ApplicationController
  include BroadcastsCardUpdates

  before_action :authenticate_user!
  before_action :set_card

  def create
    @checklist = @card.checklists.new(checklist_params)
    if @checklist.save
      @card.log_activity(current_user, "added_checklist", @checklist.title)

      # The tile's checklist progress badge appears the moment a card has any
      # checklist items, so the first checklist is a visible change for every
      # board viewer. See the note above broadcast_card_update on why the actor's
      # own response doesn't double-render.
      broadcast_card_update

      respond_to do |format|
        format.turbo_stream do
          # Append the new checklist into the modal's checklists container.
          render turbo_stream: turbo_stream.append(
            "checklists_for_#{@card.id}",
            partial: "checklists/checklist",
            locals: { checklist: @checklist }
          )
        end
        format.html { redirect_to @card.list.board }
      end
    else
      # REACHABLE from the app's own UI: the title field (cards/show, the
      # Checklist quick-add popover) is prefilled with "Checklist" but carries no
      # `required` attribute, so clearing it and pressing Add posts a blank title.
      # This used to `redirect_to` the board with generic copy — throwing the user
      # out of the card modal they were working in, for a validation error, and
      # not even saying which field was wrong.
      error = @checklist.errors.full_messages.to_sentence

      respond_to do |format|
        # 200, not 422: this form submits from inside the "modal" turbo frame, and
        # Turbo does NOT apply a turbo-stream response to a frame-targeted
        # submission when the status is 4xx — the body would be correct and the
        # user would see nothing at all. Same 200 + flash.now shape
        # ListsController#update, CommentsController#create and
        # CardsController#update_description already use.
        #
        # Only the flash. Nothing on screen needs reverting (a failed create
        # replaced nothing), and re-rendering the popover would throw away what
        # the user typed — they stay in the modal, with their input, and can fix
        # it. Same "only the flash" reasoning as CommentsController#create.
        format.turbo_stream do
          flash.now[:alert] = error
          render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
        end

        # Non-Turbo fallback. Still a redirect rather than a 422 form re-render:
        # there is no checklists/new template to render, and a bare 422 would show
        # a blank page (exactly the silent failure CommentsController#create was
        # fixed out of). The message is now the model's, not generic copy.
        format.html { redirect_to @card.list.board, alert: error }
      end
    end
  end

  # There is deliberately no #update. It existed, unreachable — a checklist's
  # title renders as a static <h3> in checklists/_checklist with no rename UI —
  # and its `update` return value was UNCHECKED, so a validation failure would
  # have redirected to the board as if it had worked. Dead code with a silent
  # trap in it, removed rather than left to be found by whoever adds renaming.
  #
  # A checklist-rename feature must re-add it WITH a failure branch (the
  # flash.now + frame-replace shape the app's other rejected writes use), and with
  # broadcast_card_update — the title isn't on the card tile, but the action
  # would then be live code.

  def destroy
    @checklist = @card.checklists.find(params[:id])
    @checklist.destroy

    # Deleting the last checklist removes the tile's progress badge entirely.
    broadcast_card_update

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(helpers.dom_id(@checklist))
      end
      format.html { redirect_to @card.list.board }
    end
  end

  private

  # broadcast_card_update comes from BroadcastsCardUpdates. No double render:
  # both actions' own turbo_stream responses target modal-internal ids only
  # (checklists_for_<card id> and checklist_<id>), never the card tile.

  def set_card
    @card = current_user.all_cards.find(params[:card_id])
  end

  def checklist_params
    params.require(:checklist).permit(:title, :position)
  end
end
