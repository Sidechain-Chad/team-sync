class CommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @card = current_user.all_cards.find(params[:card_id])
    @comment = @card.comments.new(comment_params)
    @comment.user = current_user

    if @comment.save
      # Turbo handles the stream updates via the Model callback
      # We just need to clear the form here
      render turbo_stream: turbo_stream.replace("new_comment_form", partial: "comments/form", locals: { card: @card })
    else
      # Was `head :unprocessable_entity`: no 500, but nothing rendered either, so
      # a rejected comment silently did nothing at all. Reachable from the real
      # UI — the textarea carries no `required` attribute and
      # comment_form_controller#submitOnEnter clicks submit without checking the
      # content, so Enter in an empty (focused) box posts a blank comment.
      #
      # 200 rather than 422: this form is frame-targeted (the success branch
      # above replaces the "new_comment_form" frame), and Turbo does not apply a
      # turbo-stream response to a frame-targeted submission when the status is
      # 4xx — the body would be correct and the user would see nothing. Same
      # 200 + flash.now shape ListsController#update and
      # CardsController#update_description already use.
      #
      # Only the flash: content presence is the sole validation, so there's no
      # user input worth preserving and nothing to re-render in the form. Bare
      # `render turbo_stream:` mirrors the success branch — this action speaks
      # turbo_stream on both paths, so there's no HTML branch to give a 422 to.
      flash.now[:alert] = @comment.errors.full_messages.to_sentence
      render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
    end
  end

  def destroy
    @comment = current_user.comments.find(params[:id])
    @comment.destroy

    # Remove the comment element from the DOM
    render turbo_stream: turbo_stream.remove(@comment)
  end

  private

  def comment_params
    params.require(:comment).permit(:content)
  end
end
