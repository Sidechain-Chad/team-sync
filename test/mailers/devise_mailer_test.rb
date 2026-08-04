require "test_helper"

# The mail this app sends. There was no test here at all, which is how password
# reset came to raise "Missing host to link to!" in EVERY environment behind a
# fully green suite: mailer views generate URLs, mail has no request context, and
# nothing ever rendered one.
#
# ONE mail path is live (see MailerConfigurationTest, which pins that fact):
# Devise's reset_password_instructions. :confirmable and :lockable are not
# enabled, and both send_*_notification flags are off.
class DeviseMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @mail = Devise::Mailer.reset_password_instructions(@user, "TESTTOKEN123")
  end

  # THE test. Rendering the body is what raises when default_url_options is
  # missing — deliver_now isn't needed, and neither is a controller. Everything
  # below depends on this passing, but it's asserted on its own so a failure
  # reads as "the mail doesn't render" and not as some downstream symptom.
  test "the password reset email renders" do
    assert_nothing_raised { @mail.body.to_s }
    assert @mail.body.to_s.present?, "reset instructions rendered an empty body"
  end

  test "the password reset email is addressed and titled" do
    assert_equal [@user.email], @mail.to
    assert_equal "Reset password instructions", @mail.subject
  end

  # Devise overrides `from` with Devise.mailer_sender on every message, so
  # ApplicationMailer's `default from:` alone would NOT have fixed the sender.
  # Both now read config.x.mailer_from; this asserts they agree and that neither
  # placeholder survives.
  test "the from address is the configured sender, not a generated placeholder" do
    expected = Rails.application.config.x.mailer_from

    assert_equal [expected], @mail.from
    assert_equal expected, Devise.mailer_sender
    assert_equal expected, ApplicationMailer.default[:from]
    assert_no_match(/please-change-me|from@example\.com/, @mail.from.first)
  end

  # The reset link is the entire payload of this email. A link built without a
  # host either raises (the original bug) or, worse, silently renders a relative
  # URL that is useless in a mail client.
  test "the reset link points at the configured host and carries the token" do
    host = Rails.application.config.action_mailer.default_url_options[:host]
    url  = reset_link_in(@mail)

    assert_equal host, URI.parse(url).host
    assert_equal "/users/password/edit", URI.parse(url).path
    assert_equal "TESTTOKEN123", Rack::Utils.parse_query(URI.parse(url).query)["reset_password_token"]
  end

  # Devise::Mailer inherits ActionMailer::Base by default, which resolves no
  # layout — the mail rendered as a bare fragment with no <html> and none of the
  # <style> block in layouts/mailer.html.erb. config.parent_mailer fixes that;
  # this is what stops it regressing to a naked fragment.
  test "the mailer layout wraps the message" do
    body = @mail.body.to_s

    assert_equal "mailer", Devise::Mailer._layout
    assert_includes body, "<!DOCTYPE html>"
    assert_includes body, "<html>"
    assert_includes body, "Email styles need to be inline", "layouts/mailer.html.erb <style> block missing"
    assert_includes body, "Change my password", "layout rendered but swallowed the message body"
  end

  private

  def reset_link_in(mail)
    mail.body.to_s[/https?:\/\/[^"'<\s]+reset_password_token=[^"'<\s]+/] ||
      flunk("no reset link found in the rendered email")
  end
end
