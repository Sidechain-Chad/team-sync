module MapsHelper
  # Public Mapbox token, read from ENV (loaded by dotenv-rails from
  # .env in development). In development, you MUST set MAPBOX_PUBLIC_TOKEN
  # in your .env file and restart the Rails server.
  #
  # In production, set this through your hosting platform's env-var UI
  # (Render, Heroku, Fly etc.).
  def mapbox_public_token
    ENV["MAPBOX_PUBLIC_TOKEN"]
  end
end
