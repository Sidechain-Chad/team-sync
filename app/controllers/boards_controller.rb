class BoardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, only: [:show, :edit, :update, :archive, :map]
  before_action :set_owned_board, only: [:destroy]

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

    # Starred boards (owned or shared) shown in their own section up top.
    # They still appear in their home section below too — same as Trello.
    @starred_boards = current_user.favorited_boards.order("board_favorites.created_at DESC")

    @recent_boards = recent_boards_from_session
  end

  def show
    # Preload the header's member-strip avatars onto the already-loaded
    # @board — a fixed cost (owner + members, independent of card count),
    # not a per-card N+1 like the includes below.
    ActiveRecord::Associations::Preloader.new(
      records: [@board],
      associations: { user: { avatar_attachment: :blob }, members: { avatar_attachment: :blob } }
    ).call

    # Eager-load everything the board view needs so each card on the page
    # doesn't fire its own queries for labels, members, checklist items, etc.
    # Comments aren't loaded here — the card partial only needs the count,
    # which reads from Card#comments_count (a counter cache), not the rows.
    @lists = @board.lists
                   .includes(active_cards: Card::BOARD_PAGE_INCLUDES)
                   .order(:position)

    # Stash the most recently viewed board id in session. The planner
    # uses this to offer a "back to <board>" link, since /planner has no
    # inherent board context of its own.
    session[:last_board_id] = @board.id
    track_recent_board(@board)
  end

  def archive
    # All archived cards on this board, newest first.
    @archived_cards = Card.archived
                          .where(list_id: @board.lists.select(:id))
                          .includes(:list, :labels, :members)
                          .order(updated_at: :desc)
  end

  def map
    # All non-archived cards across this board's lists that have coords.
    # Eager-load the list so the popup can show "in: List Name" without
    # an N+1 per marker.
    @located_cards = Card
                       .joins(:list)
                       .where(lists: { board_id: @board.id })
                       .where(archived_at: nil)
                       .with_location
                       .includes(:list)
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

    # Recomputed fresh (same ordering as #index) so the turbo_stream response
    # can replace the whole Starred section without a page reload.
    @starred_boards = current_user.favorited_boards.order("board_favorites.created_at DESC")

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to board_path(@board) }
    end
  end

  private

  RECENT_BOARDS_LIMIT = 6

  # Session-scoped LRU of recently visited board ids, most-recent first.
  # Per-browser and cleared on logout — acceptable for now. If cross-device
  # recency is ever wanted, upgrade path is a `board_visits` table instead
  # of this session list.
  def track_recent_board(board)
    ids = session[:recent_board_ids] || []
    ids = ids.reject { |id| id == board.id }
    ids.unshift(board.id)
    session[:recent_board_ids] = ids.first(RECENT_BOARDS_LIMIT)
  end

  # Resolves the session's id list to real boards the user still has access
  # to, in session order. Ids for boards since deleted or un-shared are
  # dropped silently, and the pruned list is written back to the session.
  def recent_boards_from_session
    ids = session[:recent_board_ids] || []
    boards_by_id = current_user.all_boards.where(id: ids).index_by(&:id)
    ordered = ids.filter_map { |id| boards_by_id[id] }

    session[:recent_board_ids] = ordered.map(&:id)
    ordered
  end

  def set_board
    # Scoped to boards the user actually has access to
    @board = current_user.all_boards.find(params[:id])
  end

  # Deleting a board is owner-only (same policy as board_users management) —
  # a shared member can view/use a board but not destroy it out from under
  # its owner.
  def set_owned_board
    @board = current_user.boards.find(params[:id])
  end

  def board_params
    # Allow name and avatar
    params.require(:board).permit(:name, :avatar)
  end
end
