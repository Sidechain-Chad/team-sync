class PlannerController < ApplicationController
  before_action :authenticate_user!

  def index
    # Resolve the board the user most recently viewed, if any. Guarded
    # through current_user.all_boards so a stale session id from a board
    # they've lost access to (revoked share, deleted board) silently
    # resolves to nil instead of leaking or 404'ing.
    @last_board = if session[:last_board_id]
      current_user.all_boards.find_by(id: session[:last_board_id])
    end

    # Month is controlled via ?year=2026&month=4 query params; defaults to today.
    today = Date.current
    @year  = (params[:year]  || today.year).to_i
    @month = (params[:month] || today.month).to_i

    # Clamp to a valid month — if someone hand-edits the URL with month=13 etc.
    begin
      @first_of_month = Date.new(@year, @month, 1)
    rescue ArgumentError
      @first_of_month = today.beginning_of_month
      @year  = @first_of_month.year
      @month = @first_of_month.month
    end

    # Calendar grid: start on Sunday of the week containing the 1st, end on
    # Saturday of the week containing the last day. Always renders 6 rows max,
    # 7 cells each = 42 cells, covering any month layout.
    grid_start = @first_of_month.beginning_of_week(:sunday)
    grid_end   = @first_of_month.end_of_month.end_of_week(:sunday)
    @days      = (grid_start..grid_end).to_a

    # Pull only dated cards from boards the user can see (owned + shared),
    # falling within the visible grid range. Eager-load the list+board so the
    # card chip can colour-code by board without N+1.
    range_start = grid_start.beginning_of_day
    range_end   = grid_end.end_of_day

    cards = Card.active
                .where(list_id: current_user.all_lists.select(:id))
                .where(due_date: range_start..range_end)
                .includes(:labels, list: :board)

    # Group by date for fast lookup in the view: { Date => [Card, Card, ...] }
    @cards_by_day = cards.group_by { |c| c.due_date.to_date }

    # Pre-compute prev/next month for the header arrows.
    @prev_month = @first_of_month - 1.month
    @next_month = @first_of_month + 1.month
  end

  def panel
    # Vertical agenda for the side panel: next 21 days of dated cards from
    # boards the user can see. Smaller window than the full calendar since
    # the sidebar is for "what's next," not "the whole month."
    range_start = Date.current.beginning_of_day
    range_end   = (Date.current + 21.days).end_of_day

    cards = Card.active
                .where(list_id: current_user.all_lists.select(:id))
                .where(due_date: range_start..range_end)
                .order(:due_date)
                .includes(:labels, list: :board)

    @cards_by_day = cards.group_by { |c| c.due_date.to_date }

    # Render without the application layout — the panel sits inside an
    # already-rendered page, so we don't want the full chrome.
    render layout: false
  end

  def map
    # Same year/month resolution as #index so the Calendar/Map toggle
    # keeps the user on the same window when they flip between views.
    today = Date.current
    @year  = (params[:year]  || today.year).to_i
    @month = (params[:month] || today.month).to_i

    begin
      @first_of_month = Date.new(@year, @month, 1)
    rescue ArgumentError
      @first_of_month = today.beginning_of_month
      @year  = @first_of_month.year
      @month = @first_of_month.month
    end

    # Only need prev/next for the header arrows, not the full grid.
    @prev_month = @first_of_month - 1.month
    @next_month = @first_of_month + 1.month

    range_start = @first_of_month.beginning_of_day
    range_end   = @first_of_month.end_of_month.end_of_day

    # Cross-board: every dated card in the visible month *with location*,
    # across every board the user can see. The map view's whole point is
    # surfacing locations regardless of which board they live on.
    @located_cards = Card.active
                         .where(list_id: current_user.all_lists.select(:id))
                         .where(due_date: range_start..range_end)
                         .with_location
                         .includes(:labels, list: :board)

    # @last_board lets the back link match #index's behaviour.
    @last_board = if session[:last_board_id]
      current_user.all_boards.find_by(id: session[:last_board_id])
    end
  end
end
