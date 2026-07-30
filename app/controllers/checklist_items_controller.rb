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
      redirect_to @checklist.card.list.board, alert: "Could not add item"
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
