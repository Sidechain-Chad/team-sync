class CardsController < ApplicationController
  before_action :authenticate_user!

  def create
    @list = List.find(params[:list_id])
    @card = @list.cards.new(card_params)

    if @card.save
      # HIRE ME MOMENT:
      # Instead of redirecting and refreshing the page, we send
      # a specific HTML snippet back to the browser to "append" the new card.
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to board_path(@list.board) }
      end
    else
      # Handle errors (for now just redirect)
      redirect_to board_path(@list.board), alert: "Could not create card"
    end
  end


  def move
    @card = Card.find(params[:id])
    @card.update(card_params)

    # --- THE MAGIC ---
    # We need to refresh the lists involved in the move.
    # If I moved a card from "Todo" to "Done", both lists look different now.

    # 1. Identify the board to broadcast to
    board = @card.list.board

    # 2. Broadcast the update to everyone looking at this board
    #    We replace the entire list DOM element with the fresh HTML.
    Turbo::StreamsChannel.broadcast_replace_to(
      board,
      target: "list_#{@card.list_id}",
      partial: "lists/list",
      locals: { list: @card.list }
    )

    # 3. Handle the edge case: If we moved it between TWO different lists,
    #    we need to update the OLD list too (to remove the card from it).
    #    (To keep this simple for the tutorial, we will just re-render
    #    ALL lists on the board. In a huge app, you'd optimize this).

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

  def update
    @card = Card.find(params[:id])
    if @card.update(card_params)
      # Broadcast change to everyone else
      broadcast_card_update

      # Respond to the user who made the edit
      respond_to do |format|
        format.html { redirect_to board_path(@card.list.board) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def card_params
    params.require(:card).permit(:title, :position, :list_id)
  end
end

def broadcast_card_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )
  end
