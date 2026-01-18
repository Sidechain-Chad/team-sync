class BoardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, only: [:show, :edit, :update, :destroy]

  def index
    # Show only the current user's boards
    @boards = current_user.boards
  end

  def show
    # Fetch all lists belonging to this board so the view can render them
    @lists = @board.lists.order(:created_at)
  end

  def new
    @board = Board.new
  end

  def create
    @board = current_user.boards.new(board_params)

    if @board.save
      redirect_to @board, notice: "Board created!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Renders the settings form
  end

  def update
    if @board.update(board_params)
      redirect_to root_path, notice: "Board updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @board.destroy
    redirect_to root_path, notice: "Board deleted."
  end

  private

  def set_board
    @board = current_user.boards.find(params[:id])
  end

  def board_params
    # Allow name and avatar
    params.require(:board).permit(:name, :avatar)
  end
end
