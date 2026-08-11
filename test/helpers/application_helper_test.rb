require "test_helper"

# current_theme is the ONE resolver both application.html.erb (the <html
# data-theme> attribute) and shared/_top_nav's switcher call — see
# theme_switching_test.rb for the response-body proof that they agree. This
# file exercises the resolver directly, including the nil case: the column is
# `null: false` with a default, so nil can never actually reach the DB (see
# AddThemeToUsers), but the fallback is defensive code precisely for a value
# that bypassed that guarantee (a console edit, a fixture, a future
# migration), and an in-memory attribute is the only way to construct that
# case without fighting the DB constraint.
class ApplicationHelperTest < ActionView::TestCase
  test "an unauthenticated visitor resolves to system" do
    stub_signed_out
    assert_equal "system", current_theme
  end

  test "each stored theme value round-trips" do
    User::THEMES.each do |theme|
      stub_signed_in(theme: theme)
      assert_equal theme, current_theme
    end
  end

  test "a nil theme falls back to light" do
    stub_signed_in(theme: nil)
    assert_equal "light", current_theme
  end

  test "an invalid stored theme falls back to light" do
    stub_signed_in(theme: "solarized")
    assert_equal "light", current_theme
  end

  private

  def stub_signed_out
    define_singleton_method(:user_signed_in?) { false }
  end

  def stub_signed_in(theme:)
    user = users(:one)
    user.theme = theme # in-memory only — never saved, so the NOT NULL/validation never run
    define_singleton_method(:user_signed_in?) { true }
    define_singleton_method(:current_user) { user }
  end
end
