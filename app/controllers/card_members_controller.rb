class CardMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card

  def create
    @user = board_member(params[:user_id])

    # Create the relationship
    @card.members << @user unless @card.members.include?(@user)

    # Notification.deliver no-ops when recipient == actor, so adding
    # yourself is silently a no-op here too.
    Notification.deliver(recipient: @user, actor: current_user, notifiable: @card, action: "added_to_card")

    broadcast_card_update

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

    broadcast_card_update

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  # Replace the small card on the board so its member avatars update for
  # everyone viewing it — a copy of CardLabelsController#broadcast_card_update,
  # which does exactly this for label pills. Members show on the tile the same
  # way labels do, so the two controllers should behave the same; this one just
  # never got it.
  #
  # Broadcast-only, no double render: the actor's own turbo_stream template
  # touches modal-internal frames only (member_row_*, assigned_members_list,
  # card_face_avatars_*), never the board tile. `replace` also targets by id, so
  # it stays idempotent regardless.
  def broadcast_card_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )
  end

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
