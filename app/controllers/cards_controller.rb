class CardsController < ApplicationController
  before_action :authenticate_user!

  def show
    @card = Card.find(params[:id])
    # Renders app/views/cards/show.html.erb (which renders _card.html.erb)
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
    @card.update(card_params)

    board = @card.list.board

    # Re-render all lists on the board to ensure order/counts update correctly
    # (In a larger app, you would optimize this to only update the old and new lists)
    board.lists.each do |list|
      Turbo::StreamsChannel.broadcast_replace_to(
        board,
        target: dom_id(list),
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
    # This renders app/views/cards/edit_description.html.erb
  end

  def update
      @card = Card.find(params[:id])
      if @card.update(card_params)
        # Broadcast change to everyone else viewing the board
        broadcast_card_update

        # FIX: Redirect to @card (the modal view) instead of the board
        # This ensures the Description frame updates in-place correctly.
        respond_to do |format|
          format.html { redirect_to @card }
        end
      else
        render :edit, status: :unprocessable_entity
      end
  end

  private

  def card_params
    params.require(:card).permit(:title, :description, :list_id, :due_date, member_ids: [])
  end

  # FIX: Moved this INSIDE the class
  def broadcast_card_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )
  end
end
