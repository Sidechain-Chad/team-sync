class BoardUsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board

  def create
    # 1. Find the user by the email address typed in the form
    user = User.find_by(email: params[:email])

    # 2. Check if user exists
    if user
      # 3. Create the connection (unless they are already connected)
      @board.board_users.find_or_create_by(user: user)
      redirect_to edit_board_path(@board), notice: "User added successfully!"
    else
      redirect_to edit_board_path(@board), alert: "User not found. Check the email."
    end
  end

  def destroy
    # Allow removing a member
    board_user = @board.board_users.find(params[:id])
    board_user.destroy
    redirect_to edit_board_path(@board), notice: "Member removed."
  end

  private

  def set_board
    # Security: Ensure only the Board Owner can add/remove people
    @board = current_user.boards.find(params[:board_id])
  end
end
