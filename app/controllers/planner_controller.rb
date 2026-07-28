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
                .where(planner_window_sql, range_start: range_start, range_end: range_end)
                .includes(:labels, list: :board)

    # Group by date for fast lookup in the view: { Date => [Card, Card, ...] }.
    # A card with both dates occupies every day it spans (Card#planner_days),
    # so it renders as a bar segment per cell; a card with only a due date
    # yields exactly one day, which is the pre-start_date behaviour unchanged.
    # Days outside the visible grid are dropped — a range can start before the
    # window or end after it.
    @cards_by_day = {}
    cards.each do |card|
      card.planner_days.each do |day|
        next unless day >= grid_start && day <= grid_end
        (@cards_by_day[day] ||= []) << card
      end
    end

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

    # Same window predicate the calendar grid uses, so a range whose span
    # overlaps the next three weeks is picked up even when its due date sits
    # outside them. Grouping by due_date alone used to put a multi-day card on
    # its due day only, which disagreed with the grid's bars.
    cards = Card.active
                .where(list_id: current_user.all_lists.select(:id))
                .where(planner_window_sql, range_start: range_start, range_end: range_end)
                .order(:due_date)
                .includes(:labels, list: :board)

    # A range card belongs on every day it spans — the agenda answers "what's on
    # my plate on day X", and in-progress work is on your plate. Reuses
    # Card#planner_days (the grid's own day expansion) rather than a second
    # implementation, so the two views can't drift. A card with no start_date
    # yields exactly one day: the pre-range behaviour, unchanged.
    window_start = range_start.to_date
    window_end   = range_end.to_date

    @cards_by_day = {}
    cards.each do |card|
      card.planner_days.each do |day|
        next unless day >= window_start && day <= window_end
        (@cards_by_day[day] ||= []) << card
      end
    end

    # Keys are inserted in due_date order, which is NOT day order once ranges
    # are involved (a card due later can start earlier). The agenda has to read
    # soonest-first, so sort by day.
    @cards_by_day = @cards_by_day.sort.to_h

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

  private

  # Which cards touch the visible grid. Two cases, deliberately kept separate
  # so the no-start_date case is byte-for-byte the old condition:
  #
  #   * no start date  -> the due date itself must fall inside the window
  #                       (a point, exactly as before start_date existed)
  #   * both dates     -> the [start, due] span must overlap the window, so a
  #                       range that begins before the month or ends after it
  #                       still renders its in-window days
  #
  # A start date with no due date matches neither: the Planner is a due-date
  # view, and such a card doesn't appear today either.
  def planner_window_sql
    <<~SQL.squish
      (start_date IS NULL AND due_date BETWEEN :range_start AND :range_end)
      OR (start_date IS NOT NULL AND due_date IS NOT NULL
          AND start_date <= :range_end AND due_date >= :range_start)
    SQL
  end
end
