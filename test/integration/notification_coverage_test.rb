require "test_helper"

# Guard for the action↔preference mapping.
#
# User#notifies? is `notification_preferences.fetch(action.to_s, true)`, so an
# action that has NO Notification::PREFERENCE_TYPES entry is delivered
# unconditionally — it silently bypasses the recipient's preferences rather than
# failing loudly. There is no way for an ordinary response assertion to catch that:
# the notification arrives, the test passes, and the user's toggle does nothing.
#
# So this scans every Notification.deliver call site in app/ and asserts each
# action it passes has an entry. Same reasoning as ZIndexLayersTest and
# BroadcastPartialsTest: a constraint invisible to normal tests, enforced at the
# source.
class NotificationCoverageTest < ActiveSupport::TestCase
  # `action:` on a Notification.deliver call. The deliver calls in this app are all
  # single-line, but the keyword can sit anywhere in the argument list, so this
  # matches the keyword itself rather than trying to parse the call.
  ACTION_KWARG = /Notification\.deliver\([^)]*action:\s*"([a-z_]+)"/

  # Any deliver call at all. Compared by COUNT against ACTION_KWARG's matches to
  # detect a call whose action isn't a string literal — a variable, a method call,
  # an interpolation — which the scan above cannot see through and which would
  # therefore be an escape hatch around this whole guard.
  #
  # Counting rather than a negative lookahead on purpose: `action:\s*(?!")` looks
  # right and is silently useless, because \s* backtracks to empty and the
  # lookahead then tests the space instead of the quote, so it matches every
  # literal call. It flagged all six real call sites on the first run.
  ANY_DELIVER_CALL = /Notification\.deliver\(/

  def self.deliver_sources
    Dir.glob(Rails.root.join("app/**/*.rb"))
  end

  def delivered_actions
    self.class.deliver_sources.flat_map do |path|
      File.read(path).scan(ACTION_KWARG).flatten.map { |action| [action, path.sub("#{Rails.root}/", "")] }
    end
  end

  test "every action passed to Notification.deliver has a PREFERENCE_TYPES entry" do
    missing = delivered_actions.reject { |action, _| Notification::PREFERENCE_TYPES.key?(action) }

    assert_empty missing, <<~MSG
      These actions are delivered but have no Notification::PREFERENCE_TYPES entry,
      so User#notifies? defaults them to TRUE and the recipient's toggle is ignored:

        #{missing.map { |action, path| "#{action.inspect} at #{path}" }.join("\n  ")}

      Add an entry (title + description) — the Settings page is data-driven, so the
      toggle appears with no view change.
    MSG
  end

  test "no deliver call hides its action behind a non-literal, which would evade this guard" do
    offenders = self.class.deliver_sources.filter_map do |path|
      source = File.read(path)
      calls   = source.scan(ANY_DELIVER_CALL).size
      literal = source.scan(ACTION_KWARG).size
      next if calls == literal

      "#{path.sub("#{Rails.root}/", "")}: #{calls} deliver call(s) but only #{literal} with a literal action:"
    end

    assert_empty offenders, <<~MSG
      Every Notification.deliver must pass `action:` as a string literal, so the
      coverage scan above can see it. A variable or interpolated action silently
      escapes the PREFERENCE_TYPES check.

        #{offenders.join("\n  ")}

      If a dynamic action is ever genuinely needed, assert its possible values
      against PREFERENCE_TYPES at that call site and exempt the file here with a note.
    MSG
  end

  # The scan is only meaningful if it actually finds the call sites. If a refactor
  # moves delivery behind a wrapper, this fails and says so, rather than passing
  # vacuously on an empty list.
  test "the scan finds every action currently in use" do
    found = delivered_actions.map(&:first).uniq.sort

    assert_equal %w[added_to_card archived attachment_added cards_created comment due_soon mention moved removed_from_card], found,
                 "the deliver-call scan found #{found.inspect} — if delivery moved behind a wrapper, " \
                 "update ACTION_KWARG or this guard is passing vacuously"
  end

  # Every entry should be a real, reachable type — an orphan entry means a dead
  # toggle sitting on the Settings page doing nothing.
  test "every PREFERENCE_TYPES entry corresponds to an action that is actually delivered" do
    delivered = delivered_actions.map(&:first).uniq
    orphans = Notification::PREFERENCE_TYPES.keys - delivered

    assert_empty orphans,
                 "these entries render a Settings toggle but nothing delivers them: #{orphans.inspect}"
  end

  test "every entry has a title and a description for the Settings page" do
    Notification::PREFERENCE_TYPES.each do |action, meta|
      assert meta[:title].present?, "#{action} needs a title"
      assert meta[:description].present?, "#{action} needs a description"
    end
  end

  # Message text is user-facing; the `else` fallback exists for old rows from
  # before a cleanup, and must not be what a CURRENT type renders.
  test "every preference type renders a specific message, not the generic fallback" do
    Notification::PREFERENCE_TYPES.each_key do |action|
      message = Notification.new(action: action).message
      assert_not_equal "sent you a notification", message,
                       "#{action} falls through to the generic fallback in Notification#message"
    end
  end
end
