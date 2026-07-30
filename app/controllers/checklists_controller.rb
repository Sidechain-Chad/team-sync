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
      redirect_to @card.list.board, alert: "Could not add checklist"
    end
  end

  # UNREACHABLE — no rename UI exists (the checklist title renders as a static
  # <h3> in checklists/_checklist), so nothing can reach this action. Left as-is
  # rather than given a broadcast: adding one would be untestable through any real
  # path. If a rename UI is ever added, it needs broadcast_card_update too — the
  # title itself isn't on the tile, but the action would then be live code.
  def update
    @checklist = @card.checklists.find(params[:id])
    @checklist.update(checklist_params)
    redirect_to @card.list.board
  end

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
