class ListsController < ApplicationController
  before_action :authenticate_user!

  def create
    @board = Board.find(params[:board_id])
    @list = @board.lists.new(list_params)

    if @list.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # 1. Insert the new list before the button
            turbo_stream.before("new_list_form", partial: "lists/list", locals: { list: @list }),

            # 2. Replace the form with a fresh, empty copy (this clears the input)
            turbo_stream.replace("new_list_form", partial: "boards/new_list_form", locals: { board: @board })
          ]
        end

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

        # FIX: Now we simply replace the header partial!
        format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(@list, :header), partial: "lists/header", locals: { list: @list }) }
      end
    else
      # If validation fails, re-render the edit form (inline)
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
