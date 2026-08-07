module ApplicationHelper
  # The value for <html data-theme="...">, resolved SERVER-SIDE so the correct
  # theme is in the first byte of the response. Doing this in JS instead is the
  # classic dark-mode flash: the browser paints the light palette, then a script
  # swaps it.
  #
  # Unauthenticated pages (Devise sign-in, password reset) get "system". They
  # have no stored preference to read, and "system" is the only answer that
  # can't be wrong on purpose — someone running a dark OS gets a dark sign-in
  # page, and it costs nothing because CSS resolves it with no JS at all.
  #
  # Falls back to "light" rather than trusting the column blindly: the value is
  # interpolated into an HTML attribute, and while User validates it on the way
  # in, a row written by a console, a fixture, or a future migration would not
  # have gone through that validation. Two checks, because the cost is one
  # `include?`.
  def current_theme
    return "system" unless user_signed_in?

    theme = current_user.theme
    User::THEMES.include?(theme) ? theme : "light"
  end
end
