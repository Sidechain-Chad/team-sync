require "test_helper"

# End-to-end password recovery, driven through the real routes and the real
# email. DeviseMailerTest proves the message renders; this proves the loop
# actually closes — that the token in the delivered mail is one the app will
# accept, and that the password genuinely changes.
#
# Sign-in is asserted by hand rather than with Devise's test helpers: the point
# is that the OLD password stops working and the NEW one starts, which is a
# property of the credentials, not of the session.
class PasswordResetFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    ActionMailer::Base.deliveries.clear
  end

  test "requesting a reset delivers exactly one email to the address" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post user_password_path, params: { user: { email: @user.email } }
    end

    assert_redirected_to new_user_session_path
    assert_equal [@user.email], ActionMailer::Base.deliveries.last.to
  end

  test "the emailed link resolves and the new password replaces the old one" do
    post user_password_path, params: { user: { email: @user.email } }

    token = reset_token_from_last_email

    # The link from the email must be a page, not a 404 or a redirect to sign-in.
    get edit_user_password_path(reset_password_token: token)
    assert_response :success
    assert_select "input[name='user[reset_password_token]'][value=?]", token

    patch user_password_path, params: {
      user: {
        reset_password_token:  token,
        password:              "brand-new-password",
        password_confirmation: "brand-new-password"
      }
    }
    # Devise signs you in on a successful reset.
    assert_redirected_to root_path

    @user.reload
    refute @user.valid_password?("password"),           "the old password still authenticates"
    assert  @user.valid_password?("brand-new-password"), "the new password does not authenticate"
  end

  test "the old password no longer signs in and the new one does" do
    post user_password_path, params: { user: { email: @user.email } }
    patch user_password_path, params: {
      user: {
        reset_password_token:  reset_token_from_last_email,
        password:              "brand-new-password",
        password_confirmation: "brand-new-password"
      }
    }
    delete destroy_user_session_path

    post user_session_path, params: { user: { email: @user.email, password: "password" } }
    assert_response :unprocessable_entity, "the old password was accepted at sign-in"

    post user_session_path, params: { user: { email: @user.email, password: "brand-new-password" } }
    assert_redirected_to root_path
  end

  # A token is single-use: Devise clears reset_password_token on success. Worth
  # pinning because the flow above would still pass if the token were left live.
  test "a reset token cannot be reused" do
    post user_password_path, params: { user: { email: @user.email } }
    token = reset_token_from_last_email

    patch user_password_path, params: {
      user: { reset_password_token: token, password: "brand-new-password", password_confirmation: "brand-new-password" }
    }

    # Sign out first, or the second attempt is rejected by Devise's
    # require_no_authentication guard (302 to root, "you are already signed in")
    # and this would assert nothing about the token at all.
    delete destroy_user_session_path

    patch user_password_path, params: {
      user: { reset_password_token: token, password: "second-attempt-pw", password_confirmation: "second-attempt-pw" }
    }
    assert_response :unprocessable_entity

    assert @user.reload.valid_password?("brand-new-password"), "the reused token overwrote the password"
  end

  # Devise is NOT running in paranoid mode (Devise.paranoid is false, see
  # config/initializers/devise.rb line 93, still commented out). So an unknown
  # address is answered with "Email not found" — which tells an unauthenticated
  # visitor whether an account exists.
  #
  # This test pins the CURRENT behaviour rather than changing it: enabling
  # paranoid mode is a product decision and is out of scope for this arc. It is
  # written so that flipping Devise.paranoid = true fails here loudly, with a
  # pointer to what to do about it, instead of silently passing.
  test "an unknown address sends no mail (and, paranoid being off, is distinguishable)" do
    refute Devise.paranoid,
      "Devise.paranoid was enabled — good, but update this test: the response " \
      "must now be identical for known and unknown addresses and this assertion " \
      "of the leak no longer applies."

    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post user_password_path, params: { user: { email: "nobody@example.com" } }
    end

    # The leak: unknown re-renders the form with an error, known redirects.
    assert_response :unprocessable_entity

    post user_password_path, params: { user: { email: @user.email } }
    assert_redirected_to new_user_session_path
  end

  private

  # Pull the token out of the delivered mail rather than off the user record, so
  # the test fails if the email carries a token the app won't accept.
  def reset_token_from_last_email
    mail = ActionMailer::Base.deliveries.last or flunk("no email was delivered")
    url  = mail.body.to_s[/https?:\/\/[^"'<\s]+reset_password_token=[^"'<\s]+/] or
      flunk("no reset link in the delivered email")

    Rack::Utils.parse_query(URI.parse(url).query).fetch("reset_password_token")
  end
end
