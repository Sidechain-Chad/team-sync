class ChecklistItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_checklist

  def create
    @item = @checklist.checklist_items.new(item_params)
    if @item.save
      redirect_to @checklist.card
    else
      redirect_to @checklist.card, alert: "Could not add item"
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
    redirect_to @checklist.card
  end

  def destroy
    @item = @checklist.checklist_items.find(params[:id])
    @item.destroy
    redirect_to @checklist.card
  end

  private

  def set_checklist
    @checklist = current_user.all_checklists.find(params[:checklist_id])
  end

  def item_params
    params.require(:checklist_item).permit(:content, :completed, :position)
  end
end
