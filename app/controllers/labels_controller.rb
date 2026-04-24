class LabelsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, except: [:cancel_edit, :cancel_new]
  before_action :set_label, only: [:edit, :update, :destroy]

  def new
    @label = @board.labels.new(color: Label::COLORS.first)
  end

  def create
    @label = @board.labels.new(label_params)
    if @label.save
      respond_to do |format|
        format.turbo_stream { render :create }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :form_errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @label.update(label_params)
      respond_to do |format|
        format.turbo_stream { render :update }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :form_errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @label.destroy
    respond_to { |format| format.turbo_stream }
  end

  # add to the controller:

  def cancel_edit
    @card  = current_user.all_cards.find(params[:card_id])
    @label = @card.list.board.labels.find(params[:label_id])
    # Renders app/views/labels/cancel_edit.html.erb (frame-wrapped)
  end

  def cancel_new
    @card = current_user.all_cards.find(params[:card_id])
    # Renders app/views/labels/cancel_new.html.erb (frame-wrapped)
  end

  private

  def set_board
    @board = current_user.all_boards.find(params[:board_id])
  end

  def set_label
    @label = @board.labels.find(params[:id])
  end

  def label_params
    params.require(:label).permit(:name, :color)
  end
end
