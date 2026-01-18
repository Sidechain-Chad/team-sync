class ListsController < ApplicationController
  before_action :authenticate_user!

  def create
    @board = Board.find(params[:board_id])
    @list = @board.lists.new(list_params)

    if @list.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to board_path(@board) }
      end
    else
      redirect_to board_path(@board), alert: "Could not create list"
    end
  end

  private

  def list_params
    params.require(:list).permit(:name)
  end
end
