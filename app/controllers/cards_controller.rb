class CardsController < ApplicationController
  before_action :authenticate_user!

  def show
    @card = Card.find(params[:id])
  end

  def new
    @list = List.find(params[:list_id])
    @card = Card.new
  end

  def create
    @list = List.find(params[:list_id])
    @card = @list.cards.new(card_params)

    if @card.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to board_path(@list.board) }
      end
    else
      redirect_to board_path(@list.board), alert: "Could not create card"
    end
  end

  def move
    @card = Card.find(params[:id])

    new_list_id  = params.dig(:card, :list_id)
    new_position = params.dig(:card, :position).to_i

    Card.transaction do
      # If the card moved to a different list, update the scope first.
      # acts_as_list will compact the old list and append to the new one;
      # insert_at then slots it into the requested position.
      if new_list_id.present? && @card.list_id.to_s != new_list_id.to_s
        @card.update!(list_id: new_list_id)
      end

      @card.insert_at(new_position) if new_position.positive?
    end

    board = @card.list.board

    # Re-render all lists on the board so positions and counts stay in sync
    # for everyone subscribed to the board's Turbo stream.
    board.lists.each do |list|
      Turbo::StreamsChannel.broadcast_replace_to(
        board,
        target: helpers.dom_id(list),
        partial: "lists/list",
        locals: { list: list }
      )
    end

    head :ok
  end

  def destroy
    @card = Card.find(params[:id])
    @card.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@card) }
      format.html { redirect_to board_path(@card.list.board) }
    end
  end

  def edit
    @card = Card.find(params[:id])
  end

  def edit_description
    @card = Card.find(params[:id])
  end

  def update_description
    @card = Card.find(params[:id])
    @card.update(card_params)

    # Render the description partial again to switch back to read mode
    render partial: "cards/description", locals: { card: @card }
  end

def update
    @card = Card.find(params[:id])

    new_list_id  = params.dig(:card, :list_id)
    list_changed = new_list_id.present? && @card.list_id.to_s != new_list_id.to_s

    if @card.update(card_params)
      broadcast_card_update

      respond_to do |format|
        if list_changed
          # Move-card popover → land back on the board.
          format.html { redirect_to board_path(@card.list.board) }
        else
          # All other updates (due date, etc.) — render the show page.
          # Since the requesting form is targeted at a Turbo frame inside
          # show.html.erb, Turbo extracts that frame's contents and the
          # modal stays open.
          format.html { redirect_to @card, status: :see_other }
        end
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def card_params
    params.require(:card).permit(
      :title, :description, :list_id, :position, :due_date, :completed
    )
  end

  def broadcast_card_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )
  end
end
