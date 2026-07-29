require "test_helper"

# Guard for the stacking ladder defined in app/assets/tailwind/application.css.
#
# Two bugs shipped from ad-hoc z-index values colliding, and BOTH passed their
# tests — the flash toast painting behind the card modal, and the list ⋯ menu /
# filter popover painting behind the bottom nav (leaving the WIP-limit "Set"
# button unclickable at 375×520). A stacking bug is invisible to assertions about
# response bodies, so the only durable defence is refusing to let new raw values
# in at all.
#
# The rule: use a named layer token (z-content / z-chrome / z-menu / z-modal /
# z-modal-panel / z-modal-menu / z-toast), never an arbitrary z-[…] value.
class ZIndexLayersTest < ActiveSupport::TestCase
  # Arbitrary-value z-index classes are what both bugs were written with, so this
  # is the pattern that must stay extinct.
  ARBITRARY_Z = /class="[^"]*\bz-\[/

  # Genuine exceptions that must clear third-party CSS we don't control.
  #
  # EMPTY, deliberately. flatpickr (99999, body-appended) and Mapbox GL (2) were
  # both checked when the ladder was built: the modal tier is pinned BELOW
  # flatpickr and the toast tier ABOVE it, both expressed as tokens, so no view
  # needs a raw escape hatch. If you add an entry here, state which third-party
  # value it's clearing and why a token can't express it.
  ALLOWLIST = [].freeze

  test "no view uses an arbitrary z-index value" do
    offenders = Dir.glob(Rails.root.join("app/views/**/*.erb")).filter_map do |path|
      rel = path.sub("#{Rails.root}/", "")
      next if ALLOWLIST.include?(rel)

      hits = File.readlines(path).each_with_index.filter_map do |line, i|
        "#{rel}:#{i + 1}" if line.match?(ARBITRARY_Z)
      end
      hits.presence
    end.flatten

    assert_empty offenders, <<~MSG
      Arbitrary z-index values found. Use a named layer token instead:

        z-content      in-page stacking
        z-chrome       static furniture (navs, side panel)
        z-menu         transient page-level overlays — and any chrome that HOSTS one
        z-modal        modal backdrop
        z-modal-panel  the panel inside it
        z-modal-menu   popovers opened from inside a modal
        z-toast        flash

      Offending lines:
        #{offenders.join("\n  ")}
    MSG
  end

  test "every layer token is defined in the theme" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))

    %w[content chrome menu modal modal-panel modal-menu toast].each do |layer|
      assert_match(/--z-index-#{Regexp.escape(layer)}:\s*\d+/, css,
                   "--z-index-#{layer} must be defined in the @theme block")
    end
  end

  test "the ladder is strictly ascending in the order the tiers are documented" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    values = %w[content chrome menu modal modal-panel modal-menu toast].map do |layer|
      css[/--z-index-#{Regexp.escape(layer)}:\s*(\d+)/, 1].to_i
    end

    assert_equal values.sort, values,
                 "layers must ascend: a transient overlay has to outrank the chrome below it (got #{values.inspect})"
    assert_equal values.uniq, values, "two layers sharing a value makes their order depend on DOM order"
  end

  test "the modal tier stays below flatpickr's body-appended calendar" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    modal_panel = css[/--z-index-modal-panel:\s*(\d+)/, 1].to_i

    # flatpickr hard-codes 99999 on .flatpickr-calendar.open and appends the
    # calendar to <body>, so it sits in the ROOT stacking context. The due-date
    # picker is opened from inside the card modal — if the modal outranked it the
    # picker would render behind the modal.
    flatpickr_z = File.read(Rails.root.join("app/assets/stylesheets/flatpickr.css"))
                      .scan(/z-index:\s*(\d+)/).flatten.map(&:to_i).max

    assert_equal 99999, flatpickr_z, "flatpickr's max z-index changed — re-check the ladder"
    assert_operator modal_panel, :<, flatpickr_z,
                    "the modal must stay below flatpickr or the due-date picker renders behind it"
  end

  test "the toast tier clears flatpickr so an error can't hide behind a date picker" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    toast = css[/--z-index-toast:\s*(\d+)/, 1].to_i
    flatpickr_z = File.read(Rails.root.join("app/assets/stylesheets/flatpickr.css"))
                      .scan(/z-index:\s*(\d+)/).flatten.map(&:to_i).max

    assert_operator toast, :>, flatpickr_z
  end
end
