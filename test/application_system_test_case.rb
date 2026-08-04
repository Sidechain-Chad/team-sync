require "test_helper"

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
  def sign_in_as(user, password: "password")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_button "Sign in"

    # Anchor on the signed-in chrome rather than on a URL: Devise redirects to
    # root, but asserting the nav exists also proves the session actually stuck
    # instead of bouncing straight back to the sign-in form.
    assert_selector "[data-controller~='dropdown']", wait: 5
  end

  # ==========================================================================
  # Drag a card onto another list with RAW POINTER EVENTS.
  # ==========================================================================
  # WHY NOT the obvious approaches — all three of these silently do nothing:
  #
  #   * Capybara's `drag_to` / Selenium's Actions#drag_and_drop — these emit
  #     mouse events (mousedown/mousemove/mouseup). SortableJS 1.15.6 binds
  #     POINTER events (pointerdown/pointermove/pointerup) when it has them, so
  #     a mouse-only sequence is never seen by the library at all.
  #   * A single pointermove straight to the target — SortableJS has
  #     `fallbackTolerance: 3` (see drag_controller.js), so a drag is not
  #     considered started until the pointer has travelled more than 3px from
  #     where it went down. One jump from A to B looks like a click.
  #   * Dispatching on the card's <turbo-frame> instead of an inner element —
  #     works, but the coordinates must still be real viewport coordinates,
  #     because SortableJS hit-tests with document.elementFromPoint().
  #
  # `forceFallback: true` is also set, which means SortableJS runs its own
  # fallback drag implementation rather than the native HTML5 drag-and-drop API
  # — so there is no dragstart/drop event to fake either.
  #
  # The sequence below therefore: pointerdown on the source, several
  # incremental pointermoves (to clear fallbackTolerance and to let SortableJS
  # hit-test its way into the target container), then pointerup. Every event is
  # `pointerType: 'mouse'`, bubbles, and carries real clientX/clientY.
  #
  # After this returns, the DOM has been mutated optimistically by SortableJS
  # and drag_controller.js has PATCHed /cards/:id/move. The response is
  # `head :ok` — nothing re-renders — so assert on the DOM, or reload and let
  # the server tell you whether it persisted.
  def drag_card_to(card, target_list)
    card_selector   = "##{ActionView::RecordIdentifier.dom_id(card)}"
    target_selector = "#list_#{target_list.id}_cards"

    assert_selector card_selector
    assert_selector target_selector

    page.execute_script(<<~JS, card_selector, target_selector)
      const [cardSelector, targetSelector] = arguments;
      const card   = document.querySelector(cardSelector);
      const target = document.querySelector(targetSelector);

      const at = (el) => {
        const r = el.getBoundingClientRect();
        return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
      };

      const fire = (el, type, pt) => el.dispatchEvent(new PointerEvent(type, {
        pointerType: 'mouse', isPrimary: true, button: 0, buttons: type === 'pointerup' ? 0 : 1,
        clientX: pt.x, clientY: pt.y, bubbles: true, cancelable: true, composed: true
      }));

      const from = at(card);
      const to   = at(target);

      fire(card, 'pointerdown', from);

      // Steps 1..N: the first few clear fallbackTolerance (3px); the rest walk
      // the pointer into the target so elementFromPoint lands inside it.
      const STEPS = 12;
      for (let i = 1; i <= STEPS; i++) {
        const pt = {
          x: from.x + ((to.x - from.x) * i) / STEPS,
          y: from.y + ((to.y - from.y) * i) / STEPS
        };
        // SortableJS's fallback listens on the document, not the source node.
        fire(document, 'pointermove', pt);
      }

      fire(document, 'pointerup', to);
    JS
  end
end
