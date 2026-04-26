class ChecklistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card

  def create
    @checklist = @card.checklists.new(checklist_params)
    if @checklist.save
      @card.log_activity(current_user, "added_checklist", @checklist.title)

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

  def update
    @checklist = @card.checklists.find(params[:id])
    @checklist.update(checklist_params)
    redirect_to @card.list.board
  end

  def destroy
    @checklist = @card.checklists.find(params[:id])
    @checklist.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(helpers.dom_id(@checklist))
      end
      format.html { redirect_to @card.list.board }
    end
  end

  private

  def set_card
    @card = current_user.all_cards.find(params[:card_id])
  end

  def checklist_params
    params.require(:checklist).permit(:title, :position)
  end
end
