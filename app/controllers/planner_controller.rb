class PlannerController < ApplicationController
  before_action :authenticate_user!

  def index
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
end
