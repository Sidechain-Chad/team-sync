require "test_helper"

class CardLabelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:one)
    @label = labels(:two) # belongs to boards(:one), same board as @card, not yet attached
    sign_in @user
  end

  test "should attach a label belonging to the card's board" do
    assert_difference('CardLabel.count', 1) do
      post card_labels_url(@card, label_id: @label.id), as: :turbo_stream
    end
    assert_response :success
    assert_includes @card.reload.labels, @label
  end

  test "should not attach a label belonging to a different board" do
    foreign_label = boards(:two).labels.create!(color: "purple")

    assert_no_difference('CardLabel.count') do
      post card_labels_url(@card, label_id: foreign_label.id), as: :turbo_stream
    end
    assert_response :not_found
  end

  test "should not attach a label to a card the user has no access to" do
    other_card = cards(:two)
    other_label = boards(:two).labels.create!(color: "orange")

    post card_labels_url(other_card, label_id: other_label.id), as: :turbo_stream

    assert_response :not_found
  end

  test "should remove a label from a card" do
    @card.labels << @label

    assert_difference('CardLabel.count', -1) do
      delete card_label_url(@card, label_id: @label.id), as: :turbo_stream
    end
    assert_response :success
  end
end
