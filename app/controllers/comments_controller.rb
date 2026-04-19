class CommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @card = Card.find(params[:card_id])
    @comment = @card.comments.new(comment_params)
    @comment.user = current_user

    if @comment.save
      # Turbo handles the stream updates via the Model callback
      # We just need to clear the form here
      render turbo_stream: turbo_stream.replace("new_comment_form", partial: "comments/form", locals: { card: @card })
    else
      # Handle error (optional for now)
      head :unprocessable_entity
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
