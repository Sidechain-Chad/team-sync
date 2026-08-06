require "test_helper"

class UserThemeTest < ActiveSupport::TestCase
  test "defaults to light so nobody's appearance changes without opting in" do
    user = User.create!(email: "theme-default@example.com", password: "password")

    assert_equal "light", user.theme
    assert_equal "light", user.reload.theme, "the default must come from the column, not just the object"
  end

  test "accepts exactly the three offered options" do
    user = users(:one)

    User::THEMES.each do |theme|
      user.theme = theme
      assert user.valid?, "#{theme} should be a valid theme but got #{user.errors[:theme]}"
    end

    assert_equal %w[light dark system], User::THEMES
  end

  test "rejects anything else" do
    user = users(:one)

    # "auto" and "" are the plausible near-misses; the last two are the reason
    # this validation exists at all — the value is interpolated into an HTML
    # attribute by the layout.
    ["auto", "", "LIGHT", "Dark", nil, %{light" onload="alert(1)}].each do |bad|
      user.theme = bad
      assert_not user.valid?, "#{bad.inspect} should be rejected"
      assert_includes user.errors.attribute_names, :theme
    end
  end

  test "an update persists" do
    user = users(:one)

    assert user.update(theme: "dark")
    assert_equal "dark", user.reload.theme

    assert user.update(theme: "system")
    assert_equal "system", user.reload.theme
  end

  test "an invalid update is refused and leaves the stored value alone" do
    user = users(:one)
    user.update!(theme: "dark")

    assert_not user.update(theme: "solarized")
    assert_equal "dark", user.reload.theme
  end

  # The theme validation is unscoped, unlike the name validation. Guard that it
  # did not accidentally get scoped to a context, which would make every save
  # path except one skip it.
  test "the validation is not scoped to a context, so no save path can bypass it" do
    user = users(:one)
    user.theme = "nonsense"

    assert_not user.valid?
    assert_raises(ActiveRecord::RecordInvalid) { user.save! }
  end

  # Regression: an avatar-only save or a deactivation must not start failing
  # because of the theme column.
  test "unrelated saves are unaffected" do
    user = users(:one)

    assert user.save, "a no-op save should still work: #{user.errors.full_messages}"
    assert_nothing_raised { user.deactivate! }
  end
end
