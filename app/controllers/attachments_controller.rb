class AttachmentsController < ApplicationController
  before_action :authenticate_user!

  def destroy
    # Scope through current_user.all_cards so users can't pass an
    # attachment id from a different user's board.
    @card = current_user.all_cards.find(params[:card_id])
    @attachment = @card.attachments.find(params[:id])

    @attachment.purge

    redirect_to @card, status: :see_other
  end
end
