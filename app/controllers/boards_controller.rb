class BoardsController < ApplicationController
  before_action :authenticate_user!

  def index
    @board =Board.all
  end

  def show
    @board = Board.find(params[:id])
    # The .includes avoids N+1 queries (A very common interview question!)
    @lists = @board.lists.includes(:cards).order(:position)
  end
end
