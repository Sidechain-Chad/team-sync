class BoardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, only: [:show, :edit, :update, :destroy, :archive]

  def index
    # Per-user favorites first (most-recently-starred at top), then the rest
    # alphabetically. LEFT JOIN brings in the current user's favorite row if
    # one exists; un-favorited boards have NULL and sort last via NULLS LAST.
    # The composite index on board_favorites(user_id, created_at) keeps this
    # fast even with many favorites per user.
    favorites_join = "LEFT JOIN board_favorites ON board_favorites.board_id = boards.id AND board_favorites.user_id = #{current_user.id.to_i}"

    @owned_boards = current_user.boards
                                .joins(favorites_join)
                                .order(Arel.sql("board_favorites.created_at DESC NULLS LAST, boards.name ASC"))

    @shared_boards = current_user.shared_boards
                                 .joins(favorites_join)
                                 .order(Arel.sql("board_favorites.created_at DESC NULLS LAST, boards.name ASC"))
  end

  def show
    # Eager-load everything the board view needs so each card on the page
    # doesn't fire its own queries for labels, members, comments-count, etc.
    @lists = @board.lists
                   .includes(
                     active_cards: [
                       :labels,
                       :members,
                       :checklists,
                       :comments,
                       { attachments_attachments: :blob }
                     ]
                   )
                   .order(:position)

    # Stash the most recently viewed board id in session. The planner
    # uses this to offer a "back to <board>" link, since /planner has no
    # inherent board context of its own.
    session[:last_board_id] = @board.id
  end

  def archive
    # All archived cards on this board, newest first.
    @archived_cards = Card.archived
                          .where(list_id: @board.lists.select(:id))
                          .includes(:list, :labels, :members)
                          .order(updated_at: :desc)
  end

  def new
    @board = Board.new
  end

  def create
    @board = current_user.boards.new(board_params)

    if @board.save
      @board.invite_users(params[:emails], current_user)
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

  def switcher
    @owned_boards  = current_user.boards.order(:name)
    @shared_boards = current_user.shared_boards.order(:name)
    render layout: false
  end

  # Toggle the board's favorite state. Stores the timestamp when starred
  # so we can later sort favorites by most-recently-starred. Responds with
  # turbo_stream so the star icon flips in place without a full reload.
  def toggle_favorite
    @board = current_user.all_boards.find(params[:id])
    favorite = current_user.board_favorites.find_by(board: @board)

    if favorite
      favorite.destroy
    else
      current_user.board_favorites.create!(board: @board)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to board_path(@board) }
    end
  end

  private

  def set_board
    # Scoped to boards the user actually has access to
    @board = current_user.all_boards.find(params[:id])
  end

  def board_params
    # Allow name and avatar
    params.require(:board).permit(:name, :avatar)
  end
end
