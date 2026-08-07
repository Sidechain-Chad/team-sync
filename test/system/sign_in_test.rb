require "application_system_test_case"

# The dullest test in the suite, on purpose. Its job is to prove the harness
# works end to end — Puma boots, Chrome launches, the session cookie survives a
# redirect, and a real page renders — so that when a richer system test fails,
# the harness is not a suspect.
class SignInTest < ApplicationSystemTestCase
  test "signing in lands on the boards index" do
    user = users(:one)

    visit new_user_session_path
    assert_selector "h2", text: "Welcome back"

    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"

    assert_selector "h1", text: "My Workspaces"
    assert_current_path root_path
  end

  test "bad credentials do not sign you in" do
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "wrong-password"
    click_button "Sign in"

    assert_no_selector "h1", text: "My Workspaces"
    assert_selector "h2", text: "Welcome back"
  end
end
