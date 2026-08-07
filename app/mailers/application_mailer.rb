class ApplicationMailer < ActionMailer::Base
  # Sourced from config.x.mailer_from (config/application.rb, MAILER_FROM env)
  # rather than the generated "from@example.com". Devise::Mailer inherits this
  # class (Devise's config.parent_mailer) but overrides `from` with
  # Devise.mailer_sender — which reads the same value, so they agree.
  default from: Rails.application.config.x.mailer_from
  layout "mailer"
end
