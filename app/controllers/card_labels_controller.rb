class CardLabelsController < ApplicationController
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
    @card = Card.find(params[:card_id])
  end

  # Replace the small card on the board so its label pills update for
  # everyone on the board (mirrors the pattern in CardsController).
  def broadcast_card_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )
  end
end
