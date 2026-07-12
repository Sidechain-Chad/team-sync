class CardMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card

  def create
    @user = board_member(params[:user_id])

    # Create the relationship
    @card.members << @user unless @card.members.include?(@user)

    # Render Turbo Stream to move the UI elements
    respond_to do |format|
      format.turbo_stream
    end
  end

  def destroy
    @user = board_member(params[:user_id])

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

  # A card member must belong to the card's board (owner or shared member) —
  # otherwise any authenticated user_id could be attached as a card member,
  # leaking board content into that user's assigned-card queries.
  def board_member(user_id)
    board = @card.list.board
    User.where(id: board.user_id).or(User.where(id: board.members.select(:id))).find(user_id)
  end
end
