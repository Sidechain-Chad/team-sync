class ChecklistItemsController < ApplicationController
  include BroadcastsCardUpdates

  before_action :authenticate_user!
  before_action :set_checklist

  def create
    @item = @checklist.checklist_items.new(item_params)
    if @item.save
      broadcast_card_update

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append(
              helpers.dom_id(@checklist, :items),
              partial: "checklist_items/checklist_item",
              locals: { checklist_item: @item }
            ),
            turbo_stream.replace(
              helpers.dom_id(@checklist),
              partial: "checklists/checklist",
              locals: { checklist: @checklist.reload }
            )
          ]
        end
        format.html { redirect_to @checklist.card.list.board }
      end
    else
      # NOT reachable from the app's own UI today: the "Add an item" field
      # (checklists/_checklist) carries `required: true`, so the browser blocks an
      # empty submit. Fixed anyway — it's reachable one markup change away, and it
      # used to `redirect_to` the board with generic copy, throwing the user out of
      # the card modal for a validation error.
      error = @item.errors.full_messages.to_sentence

      respond_to do |format|
        # 200, not 422: this form is frame-targeted (data-turbo-frame is the
        # checklist's items frame), and Turbo drops a 4xx turbo-stream response
        # for a frame-targeted submission — the user would see nothing at all.
        # Same shape as ChecklistsController#create and CommentsController#create.
        # Only the flash: a failed create replaced nothing, so there is nothing to
        # revert, and re-rendering would discard what the user typed.
        format.turbo_stream do
          flash.now[:alert] = error
          render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
        end

        # Non-Turbo fallback — redirect rather than a 422 form re-render, for the
        # same reason as ChecklistsController#create: there's no template to
        # re-render, and a bare 422 is a blank page. Message from the model.
        format.html { redirect_to @checklist.card.list.board, alert: error }
      end
    end
  end

  def update
    @item = @checklist.checklist_items.find(params[:id])
    was_completed = @item.completed
    
    if @item.update(item_params)
      if !was_completed && @item.completed
        @checklist.card.log_activity(current_user, "completed_checklist_item", @item.content)
      end
    end

    # After the update, never before: a broadcast that fires with pre-mutation
    # state is a passing-but-wrong broadcast.
    broadcast_card_update

    respond_to do |format|
      format.turbo_stream do
        # Replace both the item (for the strikethrough style) and the
        # parent checklist (for the progress bar update).
        render turbo_stream: [
          turbo_stream.replace(
            helpers.dom_id(@item),
            partial: "checklist_items/checklist_item",
            locals: { checklist_item: @item }
          ),
          turbo_stream.replace(
            helpers.dom_id(@checklist),
            partial: "checklists/checklist",
            locals: { checklist: @checklist.reload }
          )
        ]
      end
      format.html { redirect_to @checklist.card.list.board }
    end
  end

  def destroy
    @item = @checklist.checklist_items.find(params[:id])
    @item.destroy

    broadcast_card_update

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(helpers.dom_id(@item)),
          turbo_stream.replace(
            helpers.dom_id(@checklist),
            partial: "checklists/checklist",
            locals: { checklist: @checklist.reload }
          )
        ]
      end
      format.html { redirect_to @checklist.card.list.board }
    end
  end

  private

  # broadcast_card_update (BroadcastsCardUpdates) needs @card. It comes from the
  # checklist, NOT from params[:card_id]: the card id in the path is never
  # validated against the checklist, so trusting it would let a mismatched id
  # aim the broadcast at the wrong board's stream.
  #
  # No double render on any of the three actions: their own turbo_stream
  # responses target checklist_item_<id> and checklist_<id> — modal-internal ids,
  # never the card tile.
  def set_checklist
    @checklist = current_user.all_checklists.find(params[:checklist_id])
    @card = @checklist.card
  end

  def item_params
    params.require(:checklist_item).permit(:content, :completed, :position)
  end
end
