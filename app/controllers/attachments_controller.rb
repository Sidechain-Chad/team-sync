class AttachmentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @card = current_user.all_cards.find(params[:card_id])
    @card.attachments.attach(params[:file])

    @card.log_activity(current_user, "added_attachment", params[:file].original_filename)

    # Return the URL of the freshly-attached file so the editor can insert it.
    attachment = @card.attachments.last
    render json: { url: url_for(attachment), filename: attachment.filename.to_s }
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
