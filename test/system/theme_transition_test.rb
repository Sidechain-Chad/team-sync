require "application_system_test_case"

# Regression coverage for the sign-in dark-page-under-a-light-switcher bug.
#
# The Ruby side (ApplicationHelper#current_theme) was never the problem — the
# layout and the switcher already share one resolver, and theme_switching_test
# pins that agreement in the response body. The bug only exists in a REAL
# browser: Turbo Drive swaps in the new <body> on the sign-in redirect but
# never touches the pre-existing <html> element, so data-theme stays pinned at
# the signed-out "system" fallback until something re-parses the whole
# document. A Rails integration test can't see this — it only ever inspects
# one response body, never a live DOM carried across two of them — which is
# why this needs the real Chrome driver.
class ThemeTransitionTest < ApplicationSystemTestCase
  test "signing in under a dark OS renders the stored light theme without a reload" do
    user = users(:one)
    user.update!(theme: "light")
    emulate_color_scheme("dark")

    sign_in_and_land(user)

    assert_eventually(message: "data-theme stayed on the signed-out system fallback") do
      html_theme == "light"
    end
    assert_equal "light", checked_switcher_theme
  end

  test "signing in with theme system follows a dark OS immediately" do
    user = users(:one)
    user.update!(theme: "system")
    emulate_color_scheme("dark")

    sign_in_and_land(user)

    assert_eventually(message: "data-theme never settled on system") do
      html_theme == "system"
    end
    assert_equal "system", checked_switcher_theme
  end

  test "signing in with theme dark ignores a light OS immediately" do
    user = users(:one)
    user.update!(theme: "dark")
    emulate_color_scheme("light")

    sign_in_and_land(user)

    assert_eventually(message: "data-theme never settled on dark") do
      html_theme == "dark"
    end
    assert_equal "dark", checked_switcher_theme
  end

  private

  def sign_in_and_land(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
    assert_current_path root_path
  end

  def emulate_color_scheme(scheme)
    page.driver.browser.execute_cdp(
      "Emulation.setEmulatedMedia",
      features: [{ name: "prefers-color-scheme", value: scheme }]
    )
  end

  def html_theme
    page.evaluate_script("document.documentElement.getAttribute('data-theme')")
  end

  # The switcher lives inside a closed account dropdown, so its aria-checked
  # state is real DOM already rendered by the server — Capybara's default
  # visible-only matching just can't see it without opening the menu first.
  # Reading it directly is simpler than driving the dropdown open.
  def checked_switcher_theme
    page.evaluate_script(<<~JS)
      document.querySelector('[role=radio][aria-checked=true]')?.dataset.themeThemeParam
    JS
  end
end
