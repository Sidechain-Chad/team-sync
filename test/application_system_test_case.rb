require "test_helper"
require "warden/test/helpers"
require_relative "support/click_diagnostics"

# System tests run a real headless Chrome against a real Puma. Read this before
# writing one — several things in this app cannot be driven the obvious way.
#
# DRIVER: the Rails default (Capybara + selenium-webdriver + headless Chrome).
# Nothing extra needs installing: Selenium Manager resolves both Chrome for
# Testing and a version-matched chromedriver into ~/.cache/selenium on first run.
# There is deliberately no capybara-playwright-driver here — the Playwright MCP
# browser is for interactive QA, this is for CI.
#
# ============================================================================
# ACTION CABLE DOES NOT WORK HERE. This is the big one.
# ============================================================================
# config/cable.yml uses `adapter: test` in the test environment, so a
# Turbo::StreamsChannel.broadcast_* call goes into an in-process array and NEVER
# reaches the browser. That is not a small caveat in this app, because most
# board-page updates are delivered by broadcast rather than by the response:
#
#   * cards#create      — the new tile is broadcast; the RESPONSE only resets
#                         the "Add a card" trigger. A card you add in a system
#                         test WILL NOT APPEAR.
#   * cards#move        — `head :ok`. The card moves because SortableJS already
#                         moved it client-side; nothing is re-rendered.
#   * toggle_complete   — `head :no_content` from a board tile. Nothing visible
#                         happens at all.
#
# So: never write a system test that waits for a live update. It will hang for
# Capybara.default_max_wait_time and then fail with a confusing message. Assert
# on what one session can see over ordinary HTTP/Turbo — including turbo_stream
# RESPONSES, which do work fine — or assert on the record.
#
# Making broadcasts testable needs a cable adapter change for the test
# environment. That is a real decision and has not been taken.
#
# ============================================================================
# SORTABLEJS DRAGS NEED RAW POINTER EVENTS — see drag_card_to in this file.
# ============================================================================
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  # Turbo means a click is usually followed by a network round trip, so give
  # Capybara's implicit waiting more headroom than its 2s default. This raises
  # the ceiling on how long an assertion POLLS before failing; it does not add a
  # fixed delay to anything, and a passing test is not slowed by it. It is not a
  # substitute for a proper wait — if a test only passes because of this, the
  # test is wrong.
  Capybara.default_max_wait_time = 5

  # Sign in through the actual form. Devise's `sign_in` test helper manipulates
  # the session directly and has no effect on a real browser session.
  include Warden::Test::Helpers

  setup    { Warden.test_mode! }
  teardown { Warden.test_reset! }

  # flake-root-cause investigation only — see test/support/click_diagnostics.rb.
  # No-op unless CLICK_DIAGNOSTICS=1.
  setup { ClickDiagnostics.clear! if ENV["CLICK_DIAGNOSTICS"] }
  teardown { dump_click_diagnostics if ENV["CLICK_DIAGNOSTICS"] && !passed? }

  def dump_click_diagnostics
    puts "\n=== CLICK DIAGNOSTICS: #{self.class}##{name} (FAILED) ==="
    # evaluate_script returns string-keyed hashes (JSON-like), not symbols —
    # note for future edits of this file, since the first version of this
    # dump silently printed nils by digging with symbol keys.
    ClickDiagnostics.log.each_with_index do |e, i|
      before_log = (e[:before] || {})["log"] || []
      after_log  = (e[:after] || {})["log"] || []
      new_events = after_log - before_log
      reset = (e[:after] || {})["log"] && before_log.any? && after_log.empty?

      puts "-- click #{i}: #{e[:label]}"
      puts "   stale_before=#{e[:stale_before].inspect}  stale_after=#{e[:stale_after].inspect}"
      puts "   before: #{e[:before].inspect}"
      puts "   after:  #{e[:after].inspect}"
      puts "   NEW TURBO EVENTS DURING CLICK (synchronous window only): #{new_events.inspect}" if new_events.any?
      puts "   TURBO LOG WENT FROM NON-EMPTY TO EMPTY (context/window replaced under us)" if reset
      puts "   error raised: #{e[:error]}" if e[:error]
    end

    # A free extra look: by the time a test has failed, Capybara's own 5s
    # poll (or whatever the failing assertion's wait was) has already fully
    # elapsed, at zero timing cost added by us. If the page is still alive,
    # this shows whether the missing Turbo event(s) ever showed up late.
    begin
      final = Capybara.current_session.evaluate_script(ClickDiagnostics::SNAPSHOT_JS)
      puts "-- final state at failure time (no delay added): #{final.inspect}"
    rescue StandardError => e
      puts "-- final state unavailable: #{e.message}"
    end
    puts "=== end click diagnostics ===\n"
  end

  # Establish a signed-in session WITHOUT driving the login form.
  #
  # Driving the form here was measurably flaky: filling it in and clicking "Sign
  # in" left the browser on a pristine sign-in page — no error message, no console
  # error, no request — on roughly one in three runs. Reproduced with nothing but
  # three sequential sign-ins in one file. It is a click/Turbo race, not a
  # credentials or CSRF problem (forgery protection is off in test).
  #
  # Retrying or waiting harder would only have hidden it, and it is not what any
  # of these tests are about. Warden's own test helper sets the session for the
  # next request in-process, which the Capybara-managed Puma shares — so this is
  # deterministic and skips a redundant round trip per test.
  #
  # The real login UI is still covered end to end, by clicking, in
  # test/system/sign_in_test.rb — which is where a broken form SHOULD fail. Only
  # setup for other tests goes through this door.
  #
  # Callers must `visit` something afterwards: login_as takes effect on the next
  # request and navigates nowhere by itself.
  def sign_in_as(user)
    login_as(user, scope: :user)
  end

  # Press Escape without moving focus.
  #
  # `find("body").send_keys(:escape)` and friends FOCUS the element first, which
  # destroys exactly what a keyboard test is usually asserting (dropdown_controller
  # returns focus to its trigger on Esc — you cannot check that if pressing Esc
  # moved focus to <body> on the way in). An unscoped Selenium action chain sends
  # the keystroke to whatever is focused and leaves focus alone.
  #
  # It also matters WHERE the listener lives: dropdown_controller binds keydown on
  # its own element, so Esc only reaches it when focus is inside that dropdown,
  # while keyboard_controller binds on document. Focusing <body> would silently
  # skip the former and hit the latter.
  def press_escape
    page.driver.browser.action.send_keys(:escape).perform
  end

  # Wait for a known async operation to land, with a hard ceiling.
  #
  # Needed because several actions here answer `head :ok` and re-render nothing
  # (see the cable note above), so there is no DOM change for Capybara's normal
  # implicit waiting to latch onto — the only observable outcome is the record.
  # This polls the block instead.
  #
  # This is NOT "add sleeps until it passes": it waits on the specific outcome
  # under test and fails loudly with its own message at the timeout, so a genuine
  # regression still fails rather than hanging.
  def assert_eventually(timeout: 5, message: "condition was never met")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      return if yield
      flunk("#{message} (waited #{timeout}s)") if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  end

  # ==========================================================================
  # Drag a card onto another list. THE hard-won bit of this file.
  # ==========================================================================
  # drag_controller.js configures SortableJS 1.15.6 with `forceFallback: true`
  # and `fallbackTolerance: 3`. Consequences, each verified in this browser
  # rather than assumed:
  #
  # WHAT DOES NOT WORK
  #
  #   1. Capybara's `source.drag_to(target)` / Selenium's `drag_and_drop`.
  #      These press, make ONE move to the target, and release. SortableJS does
  #      not treat a drag as started until the pointer has travelled more than
  #      fallbackTolerance (3px) from where it went down, and it hit-tests the
  #      drop container with document.elementFromPoint() on each move — so a
  #      single jump reads as a click and nothing happens. No error, no warning.
  #
  #   2. SYNTHETIC pointer events dispatched from JS —
  #      `el.dispatchEvent(new PointerEvent('pointerdown', {pointerType:'mouse',
  #      clientX, clientY, bubbles: true, cancelable: true}))` followed by
  #      interpolated pointermoves on `document` and a pointerup. This LOOKS
  #      exactly right, reaches SortableJS's own listeners, and still does
  #      nothing: no `cards:drag-start` is dispatched and the card never moves.
  #      Do not spend an afternoon on this — it was tried here and abandoned.
  #      (Untrusted events are the likely reason, via SortableJS's fallback
  #      clone/elementFromPoint path, but the point is that it does not work.)
  #
  # WHAT DOES WORK — and a correction worth knowing
  #
  #   Selenium's W3C Actions API, driving the real browser input pipeline.
  #   CLAUDE.md's note that "driver-level drag helpers don't respond" is true of
  #   Playwright's `browser_drag`, but the underlying reason is NOT that drivers
  #   only emit mouse events: a trusted mouse press in any modern browser fires
  #   pointerdown/pointermove/pointerup TOO. Verified directly here — a Selenium
  #   action chain produces `pointerdown:trusted`, `pointermove:trusted`,
  #   `pointerup:trusted`. The event family was never the problem; move
  #   granularity was.
  #
  #   So the recipe is: click_and_hold, one small nudge to clear
  #   fallbackTolerance, SEVERAL incremental moves so SortableJS can hit-test
  #   its way across, a final move_to onto the target to land precisely, then
  #   release.
  #
  # AFTER THIS RETURNS: SortableJS has already moved the node optimistically and
  # drag_controller.js has PATCHed /cards/:id/move. cards#move answers
  # `head :ok` and re-renders NOTHING (the live update for other viewers is a
  # broadcast, which does not work here — see the cable note above). So assert
  # on the DOM for the optimistic move, and on the record (or a reload) for
  # persistence.
  def drag_card_to(card, target_list)
    source = find("##{ActionView::RecordIdentifier.dom_id(card)}")
    target = find("#list_#{target_list.id}_cards")

    # Viewport-relative centres: pointer moves are in viewport coordinates, and
    # elementFromPoint hit-tests in the same space.
    dx, dy = page.evaluate_script(<<~JS, source, target)
      (() => {
        const [a, b] = arguments;
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        return [
          Math.round((rb.left + rb.width / 2) - (ra.left + ra.width / 2)),
          Math.round((rb.top + rb.height / 2) - (ra.top + ra.height / 2))
        ];
      })()
    JS

    steps = 8
    step_x = (dx / steps.to_f).round
    step_y = (dy / steps.to_f).round

    # PAUSES ARE LOAD-BEARING, and this is the part that took longest to find.
    #
    # Without them the chain is delivered as one burst and the drag intermittently
    # dies half-way: `cards:drag-start` fires, only the first two pointermoves are
    # ever seen, `cards:drag-end` never comes, and the card stays put. Measured
    # directly — a burst chain that should produce 13 pointermoves delivered 2 on
    # some runs and all 13 on others, with no error either way.
    #
    # The cause is that SortableJS's fallback does real synchronous work on every
    # move (appends/positions a clone, reads bounding rects, calls
    # document.elementFromPoint), and events pushed faster than that get coalesced
    # away. A human drag emits moves milliseconds apart; a burst emits them in one
    # go. The pause restores that spacing.
    #
    # This is NOT "sleep until it passes": the pause is per-move and bounded, and
    # the test still fails loudly if the drag doesn't happen. Total added time is
    # roughly half a second per drag.
    chain = page.driver.browser.action
                .move_to(source.native)
                .click_and_hold(source.native)
                .pause(duration: 0.1)
                .move_by(0, 4) # clears fallbackTolerance (3px) so the drag starts
                .pause(duration: 0.05)

    steps.times { chain = chain.move_by(step_x, step_y).pause(duration: 0.05) }

    # Land exactly on the target regardless of rounding drift above, then one
    # more small move so SortableJS hit-tests at least once while inside it.
    chain.move_to(target.native).pause(duration: 0.05)
         .move_by(0, 5).pause(duration: 0.1)
         .release.perform
  end
end
