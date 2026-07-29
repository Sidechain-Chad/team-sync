require "test_helper"

# App-wide behaviour of the shared/_flash slot, which every error-surfacing path
# in the app routes through (board forms, list rename, WIP limit, comments,
# update_description, Devise).
#
# The distinction under test: an ERROR must persist until dismissed, a SUCCESS
# must keep auto-dismissing. A missed error is indistinguishable from the silent
# failures several arcs were spent fixing — and the 5s timer outran a deliberate
# observer twice during browser verification.
#
# These assert on data-flash-timeout-value because that is what actually drives
# the timer: flash_controller.js reads it via `static values = { timeout: ... }`
# and only arms setTimeout when it's positive. Asserting colours or icons would
# pass while the timer still fired.
class FlashTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @list = lists(:one)
    sign_in @user
  end

  # --- errors persist ---

  test "an error flash carries a zero timeout so it never auto-dismisses" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/data-flash-timeout-value="0"/, response.body,
                 "an error must not arm the auto-dismiss timer")
    assert_no_match(/data-flash-timeout-value="5000"/, response.body)
  end

  test "an error flash renders a dismiss control" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # A persistent toast with no visible way to close it would be worse than the
    # bug being fixed. The whole toast was already click-dismissible, but with no
    # affordance to show it.
    assert_match(/aria-label="Dismiss"/, response.body)
    assert_match(/fa-xmark/, response.body, "reuses the app's existing ✕ close icon")
  end

  test "an error flash is announced to assistive tech" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/role="alert"/, response.body)
  end

  # --- successes still auto-dismiss ---

  test "a success flash keeps the five second auto-dismiss" do
    @user.update_column(:name, "Existing Name")

    patch account_profile_url, params: { user: { name: "New Name" } }
    follow_redirect!

    assert_response :success
    assert_select "i.fa-circle-check"
    assert_match(/data-flash-timeout-value="5000"/, response.body,
                 "a success toast lingering is its own annoyance — keep the timer")
  end

  test "a success flash does not claim role=alert" do
    @user.update_column(:name, "Existing Name")

    patch account_profile_url, params: { user: { name: "New Name" } }
    follow_redirect!

    assert_response :success
    assert_no_match(/role="alert"/, response.body)
  end

  # --- the two variants are distinguishable, and only on the timer ---

  test "error and success variants differ in timeout, not in slot or position" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    error_body = response.body

    @user.update_column(:name, "Existing Name")
    patch account_profile_url, params: { user: { name: "New Name" } }
    follow_redirect!
    notice_body = response.body

    # Same replaceable slot in both cases — a new flash replaces a lingering one,
    # which is the existing (and intended) behaviour; there is no toast stack.
    assert_match(/id="flash"/, error_body)
    assert_match(/id="flash"/, notice_body)
    assert_match(/data-flash-timeout-value="0"/,    error_body)
    assert_match(/data-flash-timeout-value="5000"/, notice_body)
  end

  # NOTE on flash[:error]: the partial's error branch handles :alert OR :error so
  # a future caller can't have a message silently dropped, but nothing in the app
  # sets :error today and an integration test can't set it without a controller
  # that does — so it's implemented, not request-tested. Deliberately not faking a
  # test for it.
end
