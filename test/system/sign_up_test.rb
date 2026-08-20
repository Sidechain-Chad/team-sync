require "application_system_test_case"

# Mirrors sign_in_test.rb's shape and reasoning: the real click is the point
# (not sign_in_as's Warden bypass), so a verified_interaction retries it
# rather than switching to requestSubmit. Added alongside the split-screen
# auth layout since sign-up had no end-to-end coverage before it — a
# redesign is exactly when a "it still just works" regression is easiest to
# introduce without noticing.
class SignUpTest < ApplicationSystemTestCase
  test "creating an account lands on the boards index" do
    visit new_user_registration_path
    assert_selector "h2", text: "Create your account"

    fill_in "Email", with: "new-signup-#{SecureRandom.hex(4)}@example.com"
    fill_in "Password", with: "password"
    fill_in "Confirm password", with: "password"

    verified_interaction("submit the sign-up form", effect: -> { current_path == root_path }) do
      click_button "Create account"
    end

    assert_selector "h1", text: "My Workspaces"
  end

  test "a blank password does not create an account" do
    visit new_user_registration_path
    fill_in "Email", with: "blank-password-#{SecureRandom.hex(4)}@example.com"

    assert_no_difference "User.count" do
      verified_interaction("submit the sign-up form with a blank password", effect: -> { has_text?("can't be blank") }) do
        click_button "Create account"
      end
    end

    assert_no_selector "h1", text: "My Workspaces"
    assert_selector "h2", text: "Create your account"
  end
end
