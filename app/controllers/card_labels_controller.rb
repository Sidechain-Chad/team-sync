class CardLabelsController < ApplicationController
  include BroadcastsCardUpdates

  before_action :authenticate_user!
  before_action :set_card

  def create
    @label = @card.list.board.labels.find(params[:label_id])
    @card.labels << @label unless @card.labels.include?(@label)
    broadcast_card_update

    respond_to { |format| format.turbo_stream }
  end

  def destroy
    @label = @card.list.board.labels.find(params[:label_id])
    @card.card_labels.find_by(label: @label)&.destroy
    broadcast_card_update

    respond_to { |format| format.turbo_stream }
  end

  private

  def set_card
    @card = current_user.all_cards.find(params[:card_id])
  end
end
