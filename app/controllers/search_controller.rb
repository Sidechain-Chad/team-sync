class SearchController < ApplicationController
  before_action :authenticate_user!

  # Returns search results inside a <turbo-frame id="search_results">,
  # which the top-nav search dropdown swaps in via Stimulus.
  #
  # Empty query → recent boards (default state).
  # Non-empty   → ranked pg_search results across boards + cards,
  #               scoped to records the current user can access.
  def index
    @query = params[:q].to_s.strip

    if @query.blank?
      @recent_boards = current_user.all_boards
                                   .order(updated_at: :desc)
                                   .limit(5)
    else
      # pg_search returns a relation we can chain. We intersect with
      # the user's accessible scope so search never leaks across
      # workspace boundaries — important when this is sold to a
      # production company with multiple teams in one DB.
      @boards = Board.search_for(@query)
                     .where(id: current_user.all_boards.select(:id))
                     .limit(8)

      # `active` scope skips archived cards. Pre-build the accessible
      # card IDs subquery so the `where(id: ...)` filter composes
      # cleanly with pg_search's ORDER BY rank.
      accessible_card_ids = current_user.all_cards.active.select(:id)

      @cards = Card.search_for(@query)
                   .where(id: accessible_card_ids)
                   .includes(list: :board)
                   .limit(8)
    end

    render layout: false
  end
end
