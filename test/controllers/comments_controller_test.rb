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
