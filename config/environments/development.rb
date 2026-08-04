require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded any time
  # it changes. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing
  config.server_timing = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :cloudinary

  # Mail has no request context, so URL helpers in a mailer view have no host to
  # build on and raise "Missing host to link to!" — which is exactly how password
  # reset came to 500 in every environment. Every environment must set this; a
  # test guards that (see test/config/mailer_configuration_test.rb).
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # letter_opener writes each rendered message to tmp/letter_opener/ and opens it
  # in a browser rather than delivering it. The on-disk copy is the useful part:
  # it can be read and verified directly instead of trusting a popup.
  config.action_mailer.delivery_method = :letter_opener

  # Stays false, and NOT for "don't care if the mailer can't send".
  #
  # This governs DELIVERY exceptions only. The bug this arc fixes — "Missing host
  # to link to!" — is a RENDER error raised while the message is built, so it
  # raises here whether this is true or false; flipping it would not have caught
  # anything. What it does catch in development is LetterOpener's unguarded
  # `Launchy.open`, which raises Launchy::CommandNotFoundError on any box without
  # a browser command (this one — WSL). letter_opener writes the .html file
  # BEFORE it tries to open it, so with this true a perfectly rendered email 500s
  # the request after already having been "delivered" to disk. Verified in the
  # browser: it did exactly that.
  #
  # So: mail that cannot be RENDERED still blows up loudly. Mail that rendered
  # fine and merely had no browser to pop does not.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Raise error when a before_action's only/except options reference missing actions
  config.action_controller.raise_on_missing_callback_actions = true
end
