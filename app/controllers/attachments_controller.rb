class AttachmentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @card = current_user.all_cards.find(params[:card_id])
    result = CardAttachmentService.new(card: @card, user: current_user, files: [params[:file]]).call

    if result.success?
      # Return the URL of the freshly-attached file so the editor can insert it.
      attachment = result.attachments.first
      render json: { url: url_for(attachment), filename: attachment.filename.to_s }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  def destroy
    # Scope through current_user.all_cards so users can't pass an
    # attachment id from a different user's board.
    @card = current_user.all_cards.find(params[:card_id])
    @attachment = @card.attachments.find(params[:id])

    @attachment.purge_later # async — doesn't block the response on Cloudinary delete

    respond_to do |format|
      # Turbo stream: remove the attachment row from the modal in place
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(helpers.dom_id(@attachment))
      end
      # HTML fallback: redirect to the board (NOT to @card, which is frame-only)
      format.html { redirect_to @card.list.board, status: :see_other }
    end
  end
end
