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

    # Destroy the relationship
    @card.members.destroy(@user)

    # Render Turbo Stream to move the UI elements
    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def set_card
    @card = Card.find(params[:card_id])
  end
end
