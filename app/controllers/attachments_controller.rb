class AttachmentsController < ApplicationController
  before_action :authenticate_user!

  def destroy
    @attachment = ActiveStorage::Attachment.find(params[:id])
    @card = current_user.all_cards.find(@attachment.record_id)
    @attachment.purge
    redirect_to @card
  end
end
