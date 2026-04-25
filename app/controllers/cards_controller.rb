class CardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_card, only: [:show, :edit, :update, :destroy, :move, :edit_description, :update_description, :archive, :unarchive]

  def show
    # Eager-load everything the card modal needs
    @card = current_user.all_cards
                        .includes(
                          :labels,
                          :members,
                          { list: { board: [:labels, :members, :user] } },
                          { checklists: :checklist_items },
                          { comments: :user },
                          { activities: :user }
                        )
                        .find(params[:id])

    @feed = (@card.comments + @card.activities).sort_by(&:created_at).reverse
  end

  def edit
  end

  def create
    @list = current_user.all_lists.find(params[:list_id])
    @card = @list.cards.build(card_params)

    if @card.save
      @card.log_activity(current_user, "created", @list.name)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @list.board }
      end
    else
      redirect_to @list.board, alert: "Title cannot be blank."
    end
  end

  def update
    if @card.update(card_params)
      @card.log_activity(current_user, "updated")
      redirect_to @card.list.board
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @board = @card.list.board
    @card.destroy
    redirect_to @board, status: :see_other
  end

  def move
    @card.update(
      list_id: params[:list_id],
      position: params[:position].to_i + 1
    )
    head :ok
  end

  def edit_description
  end

  def update_description
    if @card.update(description: params[:card][:description])
      @card.log_activity(current_user, "edited_description")
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(@card, :description), partial: "cards/description", locals: { card: @card }) }
        format.html { redirect_to @card }
      end
    else
      render :edit_description, status: :unprocessable_entity
    end
  end

  def archive
    @card.archive!
    @card.log_activity(current_user, "archived")
    broadcast_card_remove

    respond_to do |format|
      format.html { redirect_to board_path(@card.list.board) }
    end
  end

  def unarchive
    @card.unarchive!
    @card.insert_at(@card.list.active_cards.count) if @card.position.nil?

    @card.log_activity(current_user, "unarchived")
    broadcast_card_update

    redirect_to @card.list.board
  end

  private

  def set_card
    @card = current_user.all_cards.find(params[:id])
  end

  def card_params
    params.require(:card).permit(:title, :description, :due_date, :completed)
  end

  def broadcast_card_remove
    Turbo::StreamsChannel.broadcast_remove_to(@card.list.board, target: @card)
  end

  def broadcast_card_update
    # This might need a custom broadcast if you want it to reappear in the list instantly
    # For now, simple redirect/refresh handles it.
  end
end
