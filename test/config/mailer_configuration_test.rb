require "test_helper"

# Guards on the mail CONFIGURATION rather than on any one message.
#
# Two of these read source files instead of runtime state, which is deliberate:
# a test process boots exactly one environment, so nothing running in `test` can
# observe that `production.rb` forgot default_url_options — and that omission is
# the entire bug this arc fixes. Source-scanning for a cross-environment
# invariant follows NotificationCoverageTest, which greps Notification.deliver
# call sites for the same reason.
class MailerConfigurationTest < ActiveSupport::TestCase
  ENVIRONMENT_FILES = Rails.root.glob("config/environments/*.rb").freeze

  # Config files that may read a mail ENV var. MAILER_FROM is read in
  # application.rb rather than production.rb (it needs to be set before
  # config/initializers/devise.rb runs, in every environment), so scanning
  # production.rb alone would wrongly flag it.
  MAIL_CONFIG_FILES = [
    Rails.root.join("config/application.rb"),
    Rails.root.join("config/environments/production.rb")
  ].freeze

  # Every ENV var the app's config reads for mail. Kept explicit so adding one
  # forces a decision about declaring it in render.yaml — the MAPBOX_PUBLIC_TOKEN
  # precedent: read from ENV, never declared, and therefore simply absent in
  # production until someone noticed.
  MAIL_ENV_VARS = %w[
    APP_HOST
    MAILER_FROM
    SMTP_ADDRESS
    SMTP_PORT
    SMTP_USERNAME
    SMTP_PASSWORD
    SMTP_DOMAIN
  ].freeze

  test "the running environment has a mailer host" do
    host = Rails.application.config.action_mailer.default_url_options&.fetch(:host, nil)

    assert host.present?,
      "action_mailer.default_url_options[:host] is unset in #{Rails.env}, so every " \
      "mailer view that builds a URL will raise \"Missing host to link to!\""
  end

  # The guard that stops a future environment file shipping without a host. This
  # is the assertion that, had it existed, would have failed on day one.
  test "every environment file configures a mailer host" do
    assert_equal 3, ENVIRONMENT_FILES.size, "expected development/test/production"

    ENVIRONMENT_FILES.each do |file|
      source = file.read

      assert_match(/config\.action_mailer\.default_url_options/, source,
        "#{file.basename} does not set action_mailer.default_url_options — mail " \
        "rendered in this environment will raise \"Missing host to link to!\"")
      assert_match(/host:/, source, "#{file.basename} sets default_url_options with no :host")
    end
  end

  # "from ENV, not hardcoded" — a production host baked into the repo goes stale
  # silently and sends people reset links for the wrong domain.
  test "the production mailer host comes from the environment" do
    source = Rails.root.join("config/environments/production.rb").read
    block  = source[/config\.action_mailer\.default_url_options\s*=\s*\{.*?\}/m]

    assert block, "could not find production's default_url_options assignment"
    assert_match(/ENV\[/, block, "production's mailer host is hardcoded; it must come from ENV")
  end

  # Closes the loop the Mapbox token never had: if production.rb reads it,
  # render.yaml declares it.
  # assert() with an explicit message rather than assert_match, so a failure
  # reads as one sentence instead of dumping an entire config file.
  test "render.yaml declares every mail env var the app reads" do
    config    = MAIL_CONFIG_FILES.map(&:read).join("\n")
    blueprint = Rails.root.join("render.yaml").read

    MAIL_ENV_VARS.each do |var|
      assert config.match?(/ENV(\.fetch)?[\[\(]"#{var}"/),
        "#{var} is listed in MAIL_ENV_VARS but no config file reads it"
      assert blueprint.match?(/key:\s*#{var}\b/),
        "#{var} is read by the app but not declared in render.yaml — it will " \
        "simply be missing on deploy, with no error until a user needs mail"
    end
  end

  test "no placeholder sender survives" do
    from = Rails.application.config.x.mailer_from

    assert from.present?
    assert_equal from, Devise.mailer_sender, "Devise.mailer_sender has drifted from config.x.mailer_from"
    assert_equal from, ApplicationMailer.default[:from], "ApplicationMailer's from has drifted"
    assert_no_match(/please-change-me|from@example\.com/, from)
  end

  test "test delivery is captured, never sent" do
    assert_equal :test, Rails.application.config.action_mailer.delivery_method
  end

  # ---- The mail-path audit, pinned -------------------------------------------
  #
  # This arc covered ONE mail path because only one is live. These assertions are
  # what keep that statement true: enabling a module or flag that mails will fail
  # here, pointing at the coverage it needs. That is the whole reason a total mail
  # failure could hide behind a green suite.

  test "the set of enabled Devise modules is the audited one" do
    assert_equal [
      :database_authenticatable,
      :recoverable,
      :registerable,
      :rememberable,
      :validatable
    ], User.devise_modules.sort,
      "Devise modules changed. If the new module SENDS MAIL (:confirmable, " \
      ":lockable), it needs its own coverage in test/mailers before this is updated."
  end

  test "no additional Devise notification mail is enabled" do
    refute Devise.send_password_change_notification,
      "password-change notification mail is now enabled and has no test — add one " \
      "(Devise::Mailer#password_change) before updating this."
    refute Devise.send_email_changed_notification,
      "email-changed notification mail is now enabled and has no test — add one " \
      "(Devise::Mailer#email_changed) before updating this."
  end

  # Devise::Mailer must keep inheriting ApplicationMailer, or it loses the mailer
  # layout and the mail goes back to being a bare HTML fragment.
  test "Devise mail inherits the application mailer" do
    assert_equal "ApplicationMailer", Devise.parent_mailer
    assert_operator Devise::Mailer, :<, ApplicationMailer
  end
end
