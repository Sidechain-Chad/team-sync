class BoardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_board, only: [:show, :edit, :update, :archive, :activity, :map]
  # Closing/reopening a board is owner-only, the same policy #destroy uses — a
  # shared member can view and use a board but not close it out from under its
  # owner.
  before_action :set_owned_board, only: [:destroy, :close, :reopen]

  def index
    # Per-user favorites first (most-recently-starred at top), then the rest
    # alphabetically. LEFT JOIN brings in the current user's favorite row if
    # one exists; un-favorited boards have NULL and sort last via NULLS LAST.
    # The composite index on board_favorites(user_id, created_at) keeps this
    # fast even with many favorites per user.
    favorites_join = "LEFT JOIN board_favorites ON board_favorites.board_id = boards.id AND board_favorites.user_id = #{current_user.id.to_i}"

    # Every section here is `.open` — a closed board vanishes from the index
    # entirely (owned, shared, starred and recently-viewed alike) and is reached
    # only via #closed or its direct URL.
    @owned_boards = current_user.boards.open
                                .joins(favorites_join)
                                .order(Arel.sql("board_favorites.created_at DESC NULLS LAST, boards.name ASC"))

    @shared_boards = current_user.shared_boards.open
                                 .joins(favorites_join)
                                 .order(Arel.sql("board_favorites.created_at DESC NULLS LAST, boards.name ASC"))

    # Starred boards (owned or shared) shown in their own section up top.
    # They still appear in their home section below too — same as Trello.
    # `.open` matters here specifically: favouriting is independent of closing,
    # so a starred board that gets closed would otherwise keep its Starred tile.
    @starred_boards = starred_boards_scope

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

  FEED_LIMIT = 50

  # Board-level feed of everything that happened on this board's cards:
  # Activity rows merged with Comments.
  #
  # Comments are merged at READ time rather than logged as Activity rows on
  # create. Logging would make every comment appear TWICE in the card modal,
  # which already merges comments and activities into one feed (see
  # CardsController#show's @feed) — and would duplicate the same content across
  # two tables.
  #
  # Both sides are card-scoped (neither has a board_id), so both are reached
  # through cards -> lists -> board. Board/list-level events (board renamed,
  # list created) aren't recorded at all and so aren't here — adding them would
  # mean widening the Activity table, which is out of scope.
  #
  # Each side is fetched `offset + FEED_LIMIT` deep before merging: that's what
  # guarantees the merged page is correct no matter how the two interleave (if
  # one side supplied every row, taking fewer from it could drop a row that
  # belongs).
  #
  # Pagination is offset/page-based, deliberately NOT a created_at cursor.
  # #archive_all_cards writes one Activity per card inside the same second, so
  # timestamp ties are routine rather than theoretical, and a `created_at <`
  # cursor would skip or repeat tied rows. A composite (created_at, id) cursor
  # doesn't rescue it either: the feed merges two tables with independent id
  # spaces, so there's no single id sequence to tie-break against.
  #
  # The cost of offset paging is that the fetch grows with depth — page 5 reads
  # 250 rows per side to render 50. Fine at this scale; if this feed ever gets
  # genuinely large, the fix is a real keyset cursor over a unified feed view,
  # not a deeper offset.
  #
  # The eager loads are what keep this fixed-cost — :user (+ its avatar blob,
  # since actors differ row to row, unlike the account feed's single user) and
  # card: :list for the "<card> in <list>" line. Two base queries instead of
  # one is a fixed cost, independent of row count.
  def activity
    @page  = feed_page
    offset = (@page - 1) * FEED_LIMIT
    depth  = offset + FEED_LIMIT

    card_ids = Card.where(list_id: @board.lists.select(:id)).select(:id)

    # `id: :desc` as a secondary sort is load-bearing, not cosmetic: without it
    # the DB's order among rows sharing a created_at is unspecified, so the
    # LIMIT could cut a tied group differently on two requests and page 2 would
    # repeat or skip a row. Within one table (created_at, id) is a total order.
    activities = Activity
                   .where(card_id: card_ids)
                   .includes(:user, { user: { avatar_attachment: :blob } }, card: :list)
                   .order(created_at: :desc, id: :desc)
                   .limit(depth)

    comments = Comment
                 .where(card_id: card_ids)
                 .includes(:user, { user: { avatar_attachment: :blob } }, card: :list)
                 .order(created_at: :desc, id: :desc)
                 .limit(depth)

    # Same shape the card modal's @feed uses: merge, sort desc, slice. The view
    # switches partial on the row's class.
    merged = (activities.to_a + comments.to_a).sort_by { |row| feed_sort_key(row) }.reverse

    @feed = merged.drop(offset).first(FEED_LIMIT)

    # A short page means there's nothing after it. A full page might be the last
    # one, in which case "Load more" fetches an empty page and then disappears —
    # cheap, and it avoids a count query on every request.
    @has_more  = @feed.size == FEED_LIMIT
    @next_page = @page + 1

    respond_to do |format|
      format.html
      format.turbo_stream
    end
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
      unmatched = @board.invite_users(params[:emails], current_user)
      redirect_to @board, notice: creation_notice(unmatched)
    else
      # formats: [:html] — boards/new exists only as HTML, and a bare `render
      # :new` resolves the template against the REQUEST's formats, so a
      # turbo-stream-only Accept raised MissingTemplate (a 500 on a blank name).
      # Plain full-page form, success is a redirect, so HTML + 422 is right —
      # Turbo needs a 4xx to re-render a form.
      render :new, formats: [:html], status: :unprocessable_entity
    end
  end

  def edit
    # Renders the settings form
  end

  def update
    if @board.update(board_params)
      if params.dig(:board, :remove_background) == "1" && params.dig(:board, :background).blank?
        @board.background.purge_later
      end

      redirect_to @board, notice: "Board updated successfully."
    else
      # Same fix and same reasoning as #create above.
      render :edit, formats: [:html], status: :unprocessable_entity
    end
  end

  def destroy
    @board.destroy
    redirect_to root_path, notice: "Board deleted."
  end

  def switcher
    @owned_boards  = current_user.boards.open.order(:name)
    @shared_boards = current_user.shared_boards.open.order(:name)
    render layout: false
  end

  # Closed boards, newest-closed first — the one place they're listed, and the
  # route the closing flash points at so a board is never closed into nowhere.
  # Owned AND shared: a member can't close or reopen a board, but they should
  # still be able to see that one they had access to is now closed rather than
  # have it silently vanish. The Reopen button is owner-gated in the view.
  def closed
    @closed_boards = current_user.all_boards.closed.order(closed_at: :desc)
  end

  def close
    @board.close!
    redirect_to boards_path,
                notice: "\"#{@board.name}\" is closed. You can reopen it any time from Closed boards."
  end

  def reopen
    @board.reopen!
    redirect_to board_path(@board), notice: "\"#{@board.name}\" is open again."
  end

  # Duplicate the whole board — see Board#copy_to for exactly what comes across
  # and what deliberately doesn't (labels are remapped to NEW rows on the copy;
  # favourites, archived cards and card watchers are left behind).
  #
  # Scoped through all_boards, NOT set_owned_board: anyone who can see a board may
  # take their own copy of it. Destroy/close/reopen are owner-only because they
  # affect everyone else's board; copying affects nobody, and the copy belongs to
  # whoever made it.
  #
  # No broadcast: the boards index isn't a Turbo stream target, and the copy is
  # only visible to its owner and the members carried across. Redirect to the copy.
  def copy
    source = current_user.all_boards.find(params[:id])

    begin
      new_board = source.copy_to(user: current_user, name: params[:name])
    rescue ActiveRecord::RecordInvalid => e
      # copy_to's transaction already rolled back — nothing persisted. Same shape
      # as CardsController#copy and ListsController#copy: a real page and a flash,
      # never a raw 500.
      return redirect_to board_path(source),
                         alert: "Couldn't copy this board: #{e.record.errors.full_messages.to_sentence}"
    end

    redirect_to board_path(new_board), notice: "Copied to \"#{new_board.name}\"."
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

    # Recomputed fresh (same scope and ordering as #index) so the turbo_stream
    # response can replace the whole Starred section without a page reload.
    # Going through starred_boards_scope keeps the `.open` filter — otherwise
    # starring any board would re-render the section and resurrect a tile for a
    # closed board the user had previously favourited.
    @starred_boards = starred_boards_scope

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to board_path(@board) }
    end
  end

  # Watch / stop watching this board — receive its cards' notifications and be
  # told when a card is added, without being a member of any specific card.
  # Same shape as #toggle_favorite: find the join row, destroy it if present,
  # create it if not.
  #
  # Scoped through all_boards (not set_owned_board): any board member may
  # watch, same as favoriting — this is a personal subscription, not something
  # that affects other viewers.
  #
  # DELIBERATELY NO BOARD BROADCAST, same reasoning as CardsController#toggle_watch
  # and #toggle_favorite: watch state is per-user, and the boards index isn't a
  # Turbo Stream target anyway, so there is nothing here for another viewer to
  # see live. The response replaces only the actor's own menu item.
  def toggle_watch
    @board = current_user.all_boards.find(params[:id])
    watch = current_user.board_watchers.find_by(board: @board)

    if watch
      watch.destroy
    else
      # find_or_create_by!, not create!, so a double-submit is a no-op rather
      # than a RecordNotUnique from the unique index.
      current_user.board_watchers.find_or_create_by!(board: @board)
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@board, :watch_menu_item),
          partial: "boards/watch_menu_item",
          locals: { board: @board }
        )
      end
      format.html { redirect_to @board }
    end
  end

  private

  # 1-based page for the activity feed. Anything junk, zero or negative reads as
  # page 1 — `to_i` turns "abc" and "" into 0, so one guard covers all of them.
  def feed_page
    page = params[:page].to_i
    page < 1 ? 1 : page
  end

  # Total ordering for the merged feed. created_at alone is NOT enough: rows can
  # share a timestamp (see #archive_all_cards), and Ruby's sort_by is not stable,
  # so tied rows could land in a different order on the page-1 and page-2
  # requests — which under offset paging shows up as a duplicated or missing row.
  # Adding the class name and id makes the key unique for every row, so the order
  # is fully determined and identical across requests.
  def feed_sort_key(row)
    [row.created_at, row.class.name, row.id]
  end

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

  # Starred section for #index and #toggle_favorite. One definition so the two
  # can't drift apart on the closed-board filter.
  def starred_boards_scope
    current_user.favorited_boards.open.order("board_favorites.created_at DESC")
  end

  # Resolves the session's id list to real boards the user still has access
  # to, in session order. Ids for boards since deleted or un-shared are
  # dropped silently, and the pruned list is written back to the session.
  #
  # `open_boards`, not `all_boards`: a board the user closed is usually one they
  # just visited, so it would otherwise sit at the top of Recently viewed —
  # the most visible possible place for a board that's supposed to be hidden.
  # Its id is pruned from the session here too, so it doesn't linger.
  def recent_boards_from_session
    ids = session[:recent_board_ids] || []
    boards_by_id = current_user.open_boards.where(id: ids).index_by(&:id)
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
    # Allow name, avatar, and background. remove_background is handled
    # separately in #update — it's not a model attribute.
    params.require(:board).permit(:name, :avatar, :background)
  end

  # Wording matches BoardUsersController#create's single-add flash
  # ("User not found. Check the email.") rather than inventing a second
  # phrasing for the same failure.
  def creation_notice(unmatched_emails)
    return "Board created successfully!" if unmatched_emails.empty?

    plural = unmatched_emails.size > 1
    "Board created successfully! User#{"s" if plural} not found for " \
      "#{unmatched_emails.join(", ")}. Check the email#{"s" if plural}."
  end
end
