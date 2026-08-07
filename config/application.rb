require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TeamSync
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # The address every outgoing mail is sent FROM. Read here, once, because two
    # unrelated places need the same value and they must not drift:
    #
    #   * ApplicationMailer's `default from:` — every app mailer
    #   * Devise.mailer_sender (config/initializers/devise.rb) — Devise ALWAYS
    #     sets `from` from this, overriding the parent mailer's default, so
    #     fixing only ApplicationMailer would have left Devise mail sending as
    #     the `please-change-me-at-config-initializers-devise@example.com`
    #     placeholder.
    #
    # application.rb is evaluated before config/initializers/*, so devise.rb can
    # read this. A plain ENV read in both files would be two fallbacks to keep in
    # sync; this is one.
    config.x.mailer_from = ENV["MAILER_FROM"].presence || "no-reply@teamsync.local"
  end
end
