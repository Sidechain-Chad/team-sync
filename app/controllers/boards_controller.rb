class BoardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, only: [:show, :edit, :update, :destroy]

  def index
    # Boards I created
    @created_boards = current_user.boards

    # Boards shared with me
    @shared_boards = current_user.shared_boards
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
      # NEW: Process the invites if any emails were entered
      invite_users_from_params if params[:emails].present?

      redirect_to @board, notice: "Board created successfully!"
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

  def invite_users_from_params
    # 1. Split the string by commas (e.g. "bob@test.com, alice@test.com")
    emails = params[:emails].split(',').map(&:strip)

    emails.each do |email|
      # 2. Find the user (if they exist)
      user = User.find_by(email: email)

      # 3. Add them to the board if found
      if user && user != current_user
        @board.board_users.create(user: user)
      end
    end
  end

  def set_board
    @board = current_user.boards.find(params[:id])
  end

  def board_params
    # Allow name and avatar
    params.require(:board).permit(:name, :avatar)
  end
end
