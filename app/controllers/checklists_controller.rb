class ChecklistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card

  def create
    @checklist = @card.checklists.new(checklist_params)
    if @checklist.save
      @card.log_activity(current_user, "added_checklist", @checklist.title)
      redirect_to @card
    else
      redirect_to @card, alert: "Could not add checklist"
    end
  end

  def update
    @checklist = @card.checklists.find(params[:id])
    @checklist.update(checklist_params)
    redirect_to @card
  end

  def destroy
    @checklist = @card.checklists.find(params[:id])
    @checklist.destroy
    redirect_to @card
  end

  private

  def set_card
    @card = current_user.all_cards.find(params[:card_id])
  end

  def checklist_params
    params.require(:checklist).permit(:title, :position)
  end
end
