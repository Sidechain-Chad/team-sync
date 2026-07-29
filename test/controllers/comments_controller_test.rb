require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:one)
    @comment = comments(:one) # authored by users(:one), on cards(:one)
    sign_in @user
  end

  test "should create comment on an accessible card" do
    assert_difference('Comment.count', 1) do
      post card_comments_url(@card), params: { comment: { content: "Nice card" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "should not create comment on a card the user has no access to" do
    other_card = cards(:two)

    assert_no_difference('Comment.count') do
      post card_comments_url(other_card), params: { comment: { content: "Injected" } }, as: :turbo_stream
    end
    assert_response :not_found
  end

  # --- failed create must give feedback, not silence ---
  #
  # This was `head :unprocessable_entity`: no 500, but nothing rendered either, so
  # a blank comment silently did nothing. Reachable from the real UI — the
  # textarea has no `required` attribute and comment_form_controller's
  # submitOnEnter clicks submit without checking the content, so Enter in an
  # empty (focused) box submits blank.

  test "a blank comment conveys the validation error instead of failing silently" do
    assert_no_difference "Comment.count" do
      post card_comments_url(@card), params: { comment: { content: "" } }, as: :turbo_stream
    end

    # 200, not 422: the comment form is frame-targeted (the success branch
    # replaces the "new_comment_form" frame), and Turbo drops a 4xx turbo-stream
    # response for a frame-targeted submission — the user would see nothing.
    assert_response :success
    assert_match(/turbo-stream action="replace" target="flash"/, response.body)
    assert_match(/Content can&#39;t be blank/, response.body,
                 "the error must actually reach the user")
  end

  test "a whitespace-only comment is also rejected with feedback" do
    assert_no_difference "Comment.count" do
      post card_comments_url(@card), params: { comment: { content: "   " } }, as: :turbo_stream
    end

    assert_response :success
    assert_match(/Content can&#39;t be blank/, response.body)
  end

  test "a blank comment does not raise for a turbo-stream-only request" do
    assert_no_difference "Comment.count" do
      post card_comments_url(@card), params: { comment: { content: "" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "regression: a valid comment still creates and streams the reset form" do
    assert_difference "Comment.count", 1 do
      post card_comments_url(@card), params: { comment: { content: "Still works" } }, as: :turbo_stream
    end

    assert_response :success
    # The success branch is unchanged: it replaces the form frame, and must NOT
    # have gained a flash.
    assert_match(/turbo-stream action="replace" target="new_comment_form"/, response.body)
    assert_no_match(/target="flash"/, response.body)
    assert_equal "Still works", Comment.order(:id).last.content
  end

  test "should destroy own comment" do
    assert_difference('Comment.count', -1) do
      delete card_comment_url(@card, @comment), as: :turbo_stream
    end
    assert_response :success
  end

  test "should not destroy another user's comment" do
    other_comment = comments(:two) # authored by users(:two)

    assert_no_difference('Comment.count') do
      delete card_comment_url(cards(:two), other_comment), as: :turbo_stream
    end
    assert_response :not_found
  end
end
