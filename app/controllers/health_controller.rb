# Database-backed health check for Render's `healthCheckPath` — deliberately
# separate from Rails' default `/up` (`rails_health_check`), which only proves
# the process booted and never touches the database. That gap is exactly how
# 23 consecutive deploys reported healthy while every page 500'd: the app
# server was up, Postgres was not.
#
# Inherits ActionController::Base directly, not ApplicationController — this
# must stay unauthenticated and dependency-free no matter what a future
# `before_action` gets added to ApplicationController for the rest of the app.
#
# Database only, on purpose: Cloudinary and Mapbox are external services this
# app degrades gracefully without (a missing map token renders an error card,
# not a 500 — see MapsHelper). Coupling deploy health to a third party's
# uptime would take the whole app out of rotation for an outage that isn't
# ours, which is a worse failure mode than the one this fixes.
class HealthController < ActionController::Base
  def show
    ActiveRecord::Base.connection.execute("SELECT 1")
    head :ok
  rescue StandardError
    head :service_unavailable
  end
end
