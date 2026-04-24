class CardMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card

  def create
    @user = User.find(params[:user_id])

    # Create the relationship
    @card.members << @user unless @card.members.include?(@user)

    # Render Turbo Stream to move the UI elements
    respond_to do |format|
      format.turbo_stream
    end
  end

  def destroy
    @user = User.find(params[:user_id])

    # Destroy the join row, not the user. find_by + safe-nav
    # avoids raising if it was already removed in another tab.
    @card.card_members.find_by(user: @user)&.destroy

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def set_card
    @card = current_user.all_cards.find(params[:card_id])
  end
end
