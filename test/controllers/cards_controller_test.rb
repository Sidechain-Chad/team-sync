require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board_one = boards(:one)
    @list_one = lists(:one)
    @list_two = lists(:two)
    @card = cards(:one)
    sign_in @user
  end

  test "should update card and log move activity when list changes" do
    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { list_id: @list_two.id } }
    end

    assert_redirected_to board_url(@list_two.board)
    @card.reload
    assert_equal @list_two.id, @card.list_id
    
    activity = Activity.last
    assert_equal "moved", activity.action
    assert_equal "#{@list_one.name} to #{@list_two.name}", activity.description
    assert_equal "moved this card from #{@list_one.name} to #{@list_two.name}", activity.message
  end

  test "should update card and log general update activity when list does not change" do
    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { title: "Updated Title" } }
    end

    assert_redirected_to board_url(@board_one)
    @card.reload
    assert_equal "Updated Title", @card.title
    
    activity = Activity.last
    assert_equal "renamed", activity.action
  end
end
