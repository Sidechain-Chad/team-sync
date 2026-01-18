class CardsController < ApplicationController
  before_action :authenticate_user!

  def move
    @card = Card.find(params[:id])

    # 1. Update the connection to the new list (if it changed)
    #    and the new position.
    #    acts_as_list handles the reordering of other cards automatically!
    @card.update(card_params)

    # 2. Respond with OK (we don't need to render a view)
    head :ok
  end

  private

  def card_params
    params.require(:card).permit(:position, :list_id)
  end
end
