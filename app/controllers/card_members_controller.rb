class CardMembersController < ApplicationController
  include BroadcastsCardUpdates

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
    removed = @card.card_members.find_by(user: @user)&.destroy

    # Mirrors #create's added_to_card: the removed user is the only recipient, not
    # the card's subscribers — this is about them, not about the card changing.
    # Gated on a row having actually been destroyed, so the already-removed case
    # (a second tab, a double submit) doesn't notify a second time. Removing
    # yourself notifies nobody: Notification.deliver no-ops when recipient ==
    # actor, same as #create.
    if removed
      Notification.deliver(recipient: @user, actor: current_user, notifiable: @card, action: "removed_from_card")
    end

    broadcast_card_update

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  # broadcast_card_update comes from BroadcastsCardUpdates — the card's member
  # avatars render on its board tile, so every viewer needs the fresh tile.
  #
  # No double render: the actor's own turbo_stream template touches
  # modal-internal frames only (member_row_*, assigned_members_list,
  # card_face_avatars_*), never the board tile.

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
