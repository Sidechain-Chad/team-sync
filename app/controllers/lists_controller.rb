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

  def edit
    @list = List.find(params[:id])
  end

  def update
    @list = List.find(params[:id])
    if @list.update(list_params)
      respond_to do |format|
        format.html { redirect_to board_path(@list.board) }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("list_#{@list.id}_header", partial: "lists/header", locals: { list: @list }) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @list = List.find(params[:id])
    @list.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@list) }
      format.html { redirect_to board_path(@list.board) }
    end
  end

  def move
    @list = List.find(params[:id])
    @list.insert_at(list_params[:position].to_i)
    head :ok
  end

  private

  def list_params
    params.require(:list).permit(:name, :position)
  end
end
