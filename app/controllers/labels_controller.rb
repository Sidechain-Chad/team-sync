class LabelsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, except: [:cancel_edit, :cancel_new]
  before_action :set_label, only: [:edit, :update, :destroy]
  # These actions render a picker row for a specific card (card_id comes from
  # the link/form query string) — resolve it here, scoped, rather than each
  # view doing its own raw Card.find(params[:card_id]).
  before_action :set_card, only: [:new, :create, :edit, :update]
  before_action :set_optional_card, only: [:destroy]

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
        format.turbo_stream do
          # Every card carrying this label gets re-broadcast (its pill may
          # have changed color/name) — eager-load so that's a flat query
          # count instead of an N+1 across the board.
          @cards_to_broadcast = @label.cards.with_board_page_includes
          render :update
        end
      end
    else
      respond_to do |format|
        format.turbo_stream { render :form_errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    # Every card on the board gets re-broadcast (the deleted label's pill
    # needs to disappear from any card that had it) — eager-load for the
    # same reason as #update above.
    @cards_to_broadcast = Card.with_board_page_includes.where(list: @board.lists)
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

  def set_card
    @card = current_user.all_cards.find(params[:card_id])
  end

  def set_optional_card
    @card = current_user.all_cards.find(params[:card_id]) if params[:card_id].present?
  end

  def label_params
    params.require(:label).permit(:name, :color)
  end
end
