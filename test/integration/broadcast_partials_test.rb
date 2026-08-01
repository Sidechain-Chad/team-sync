require "test_helper"

# Guard for partials that are broadcast to a SHARED stream.
#
# `cards/_card` is pushed to the board's stream by
# BroadcastsCardUpdates#broadcast_card_update (and by the full-list replaces in
# CardsController / ListsController), rendered through
# ApplicationController.renderer — which has NO session. Inside a broadcast render
# `current_user` is nil, so a per-user branch in one of these partials fails one of
# two ways, both bad:
#
#   1. It raises on nil, breaking EVERY tile broadcast in the app — card edits,
#      drags, labels, members, attachments, checklists. A cross-feature regression
#      from a one-line change in an unrelated feature.
#   2. Or it renders the signed-out branch for everyone, so per-user state silently
#      disappears the moment anybody touches the card and reappears on reload.
#
# Even where it "works", the body is identical for every recipient, so per-user
# state would be shown to the wrong people — the class of bug the notification
# badge and the per-member account rows each had.
#
# The rule: these partials render the same HTML for everyone. Per-user state goes
# in a separate element rendered in request context (see boards/_watched_cards) and
# is applied client-side. The tile watch badge is the worked example.
#
# This is a grep guard for the same reason as ZIndexLayersTest: the constraint is
# invisible to ordinary response assertions and will rot the next time someone
# wants per-user tile state.
class BroadcastPartialsTest < ActiveSupport::TestCase
  # Partials rendered into a shared (non-per-user) Turbo stream.
  BROADCAST_PARTIALS = %w[
    app/views/cards/_card.html.erb
    app/views/cards/_tile_title.html.erb
    app/views/cards/_label_pills.html.erb
    app/views/cards/_due_pill.html.erb
    app/views/lists/_list.html.erb
    app/views/lists/_header.html.erb
    app/views/lists/_card_count.html.erb
  ].freeze

  # Anything that reads the session or the signed-in user.
  SESSION_DEPENDENT = /\b(current_user|user_signed_in\?|session\[|cookies\[)/

  # ERB comments blanked out, line numbering preserved. Needed because the very
  # partials this guards carry comments EXPLAINING the rule, which name
  # current_user in prose — the first version of this test failed on its own
  # documentation. A single-line filter isn't enough: `<%# … %>` comments here span
  # many lines.
  def self.code_lines(source)
    stripped = source.gsub(/<%#.*?%>/m) { |block| "\n" * block.count("\n") }
    stripped.lines
  end

  test "no partial broadcast to a shared stream reads current_user or the session" do
    offenders = BROADCAST_PARTIALS.flat_map do |rel|
      path = Rails.root.join(rel)
      next [] unless File.exist?(path)

      self.class.code_lines(File.read(path)).each_with_index.filter_map do |line, i|
        "#{rel}:#{i + 1}: #{line.strip}" if line.match?(SESSION_DEPENDENT)
      end
    end

    assert_empty offenders, <<~MSG
      Session-dependent code found in a partial that is broadcast to a shared stream.

      These render through ApplicationController.renderer, which has no session:
      current_user is nil there. Put the per-user state in its own element rendered
      in request context (see boards/_watched_cards + watch_badge_controller.js)
      and apply it client-side.

      Offending lines:
        #{offenders.join("\n  ")}
    MSG
  end

  # The list above only helps if it still names real files.
  test "every listed broadcast partial exists" do
    missing = BROADCAST_PARTIALS.reject { |rel| File.exist?(Rails.root.join(rel)) }

    assert_empty missing,
                 "BROADCAST_PARTIALS names files that no longer exist — rename or remove them: #{missing.inspect}"
  end

  # The tile badge's contract, asserted against the file rather than a response:
  # it must be unconditional. A `<% if %>` around it would be the first step back
  # towards per-user state in the tile.
  test "the tile watch badge is rendered unconditionally" do
    tile = File.read(Rails.root.join("app/views/cards/_card.html.erb"))
    code = self.class.code_lines(tile).join

    assert_match(/data-controller="watch-badge"/, code)
    assert_match(/class="hidden items-center gap-1"/, code,
                 "the badge ships hidden; the browser decides visibility")
    assert_no_match(/watched_by\?/, code,
                    "watched_by? needs a user — it cannot be called from a broadcast render")
  end
end
