class AttachmentsController < ApplicationController
  include BroadcastsCardUpdates

  before_action :authenticate_user!

  def create
    @card = current_user.all_cards.find(params[:card_id])
    result = CardAttachmentService.new(card: @card, user: current_user, files: [params[:file]]).call

    if result.success?
      @card.attachments.reload
      broadcast_card_update

      @card.subscribers.each do |subscriber|
        Notification.deliver(recipient: subscriber, actor: current_user, notifiable: @card, action: "attachment_added")
      end

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

    # Load-bearing: purge_later deletes the attachment row synchronously and only
    # queues the BLOB purge, so the DB is already correct — but @card.attachments
    # was cached by the .find above, and without dropping that cache the
    # re-rendered tile would cheerfully show the cover that was just removed.
    @card.attachments.reload
    broadcast_card_update

    respond_to do |format|
      # Turbo stream: remove the attachment row from the modal in place
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(helpers.dom_id(@attachment))
      end
      # HTML fallback: redirect to the board (NOT to @card, which is frame-only)
      format.html { redirect_to @card.list.board, status: :see_other }
    end
  end

  # broadcast_card_update comes from BroadcastsCardUpdates. A cover is the most
  # visually obvious thing on a tile, so a stale one is the most obvious possible
  # divergence between two viewers.
  #
  # Broadcasts for NON-images too: Card#cover_image skips them, but cards/_card
  # also renders a paperclip badge with attachments.size, which every file type
  # changes.
  #
  # No double render: neither action's own response includes the board tile
  # (#create returns JSON for the tiptap editor, #destroy removes one attachment
  # row).
end
