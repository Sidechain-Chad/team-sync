require "test_helper"

class ThemeSwitchingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
  end

  # ---- <html data-theme> is rendered server-side ----
  #
  # This is the anti-flash requirement, and the reason it is asserted on the raw
  # body rather than through a helper unit test: what matters is that the
  # attribute is in the HTML the browser receives, before any JS runs.

  test "html carries data-theme matching the stored preference" do
    User::THEMES.each do |theme|
      @user.update!(theme: theme)
      sign_in @user
      get root_path

      assert_response :success
      assert_match(/<html data-theme="#{theme}"/, response.body,
                   "the #{theme} preference must be in the markup, not applied later by JS")
      sign_out @user
    end
  end

  test "unauthenticated pages default to system" do
    get new_user_session_path

    assert_response :success
    assert_match(/<html data-theme="system"/, response.body,
                 "a signed-out visitor has no stored preference; system is the only " \
                 "answer that can't be deliberately wrong, and CSS resolves it for free")
  end

  test "a stored value that somehow bypassed validation falls back to light, not into the attribute" do
    # update_column skips validations, standing in for a console edit, a fixture,
    # or a future migration writing a value the model would have refused.
    @user.update_column(:theme, %{dark" onload="alert(1)})
    sign_in @user
    get root_path

    assert_response :success
    assert_match(/<html data-theme="light"/, response.body)
    assert_no_match(/onload=/, response.body)
  end

  # ---- The switcher renders, with the current option indicated ----

  test "the account menu renders all three options with the current one checked" do
    @user.update!(theme: "dark")
    sign_in @user
    get root_path

    assert_select "[data-controller=theme] [role=radiogroup]" do
      assert_select "[role=radio]", 3
      assert_select "[data-theme-theme-param=light]",  1
      assert_select "[data-theme-theme-param=dark]",   1
      assert_select "[data-theme-theme-param=system]", 1

      # Exactly one checked, and it is the stored one.
      assert_select "[role=radio][aria-checked=true]", 1
      assert_select "[data-theme-theme-param=dark][aria-checked=true]", 1
    end
  end

  test "the checked option follows the stored preference" do
    User::THEMES.each do |theme|
      @user.update!(theme: theme)
      sign_in @user
      get root_path

      assert_select "[data-theme-theme-param=#{theme}][aria-checked=true]", 1,
                    "#{theme} should be the indicated option"
      assert_select "[role=radio][aria-checked=true]", 1,
                    "only one option may be indicated at a time"
      sign_out @user
    end
  end

  test "every option renders a checkmark slot so toggling it cannot reflow the menu" do
    sign_in @user
    get root_path

    # The controller toggles `invisible` on these; they must all exist up front.
    assert_select "[data-theme-check]", 3
    assert_select "[data-theme-check].invisible", 2, "the two unselected options start hidden"
  end

  # The radiogroup contract, rendered server-side. If all three were tabbable,
  # tabbing past the account menu would cost three key presses instead of one.
  test "only the checked option is in the tab order" do
    @user.update!(theme: "system")
    sign_in @user
    get root_path

    assert_select "[role=radio][tabindex='0']", 1
    assert_select "[data-theme-theme-param=system][tabindex='0']", 1
    assert_select "[role=radio][tabindex='-1']", 2
  end

  # The roles have to be ones this codebase actually implements. DropdownAriaTest
  # bans menuitem* app-wide because role="menu" forbids the forms these dropdowns
  # contain, and an orphaned menuitemradio is worse than no role — this asserts
  # the switcher did not reintroduce that.
  test "the switcher uses radiogroup semantics, not an orphaned menu role" do
    sign_in @user
    get root_path

    assert_select "[role=radiogroup]", 1
    assert_select "[role=radiogroup][aria-labelledby]", 1, "the group needs an accessible name"
    assert_select "[role=menuitemradio]", 0
    assert_select "[role=menu]", 0
  end

  # ---- Persisting ----

  test "patching the theme persists it and returns no content" do
    sign_in @user

    patch account_theme_path, params: { theme: "dark" }, as: :json

    assert_response :no_content
    assert_equal "dark", @user.reload.theme
  end

  test "each of the three values is accepted" do
    sign_in @user

    User::THEMES.each do |theme|
      patch account_theme_path, params: { theme: theme }, as: :json
      assert_response :no_content
      assert_equal theme, @user.reload.theme
    end
  end

  test "an invalid theme is rejected with 422 and does not change the stored value" do
    @user.update!(theme: "dark")
    sign_in @user

    patch account_theme_path, params: { theme: "solarized" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "dark", @user.reload.theme
  end

  test "an injection attempt is rejected rather than stored" do
    sign_in @user

    patch account_theme_path, params: { theme: %{light" onload="alert(1)} }, as: :json

    assert_response :unprocessable_entity
    assert_equal "light", @user.reload.theme
  end

  test "the endpoint requires authentication" do
    # 401, not a redirect: the switcher calls this as JSON, and Devise's failure
    # app only redirects navigational formats. A redirect here would be worse
    # anyway — the fetch would follow it and quietly "succeed" against the
    # sign-in page.
    patch account_theme_path, params: { theme: "dark" }, as: :json

    assert_response :unauthorized
  end

  # The switcher is fired from the top nav, which renders on every page — so the
  # endpoint must not depend on having come from the settings page.
  test "the theme can be changed from any page, not just account settings" do
    sign_in @user
    get board_path(boards(:one))

    patch account_theme_path, params: { theme: "system" }, as: :json

    assert_response :no_content
    assert_equal "system", @user.reload.theme
  end

  # ---- The mailer layout must stay unthemed ----
  #
  # Emails have no <html data-theme>, no stylesheet link, and no business
  # following an in-app appearance preference — a dark-mode user's colleagues
  # read the same email they do.
  test "the mailer layout is unaffected by the theme" do
    @user.update!(theme: "dark")

    layout = File.read(Rails.root.join("app/views/layouts/mailer.html.erb"))

    assert_no_match(/data-theme/, layout)
    assert_no_match(/stylesheet_link_tag/, layout)
  end
end
