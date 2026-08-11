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

    # THE textbook flaky click in this app — ApplicationSystemTestCase's own
    # comment on sign_in_as documents it directly: clicking "Sign in" left the
    # browser on a pristine sign-in page, no error anywhere, on roughly one in
    # three runs. This file exists specifically to test the real click (that's
    # the whole point of not using sign_in_as here), so the fix is the retry
    # primitive, not switching to requestSubmit like the setup path did.
    verified_interaction("submit the sign-in form", effect: -> { current_path == root_path }) do
      click_button "Sign in"
    end

    assert_selector "h1", text: "My Workspaces"
  end

  test "bad credentials do not sign you in" do
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "wrong-password"

    # The effect has to be something that proves a round trip actually
    # happened, not just "still on the sign-in page" — that's also exactly
    # what a no-op click looks like. Devise's own rejection message
    # ("Invalid Email or password.") only appears after a real failed
    # attempt is processed, so it's the one signal that distinguishes
    # "correctly rejected" from "never submitted."
    verified_interaction("submit the sign-in form with bad credentials", effect: -> { has_text?("Invalid Email or password") }) do
      click_button "Sign in"
    end

    assert_no_selector "h1", text: "My Workspaces"
    assert_selector "h2", text: "Welcome back"
  end
end
