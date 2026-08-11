# Temporary diagnostic harness for the flake-root-cause investigation.
# Not required anywhere by default — opt in with CLICK_DIAGNOSTICS=1.
#
# Hypothesis under test: a Selenium/Capybara click resolves a real DOM node,
# but Turbo Drive replaces <body> (or a frame) before the click actually
# dispatches, so the click lands on a node that is no longer attached to the
# document — no effect, no error, no request.
#
# This wraps every Capybara::Node::Element#click with:
#   - a staleness check immediately before and immediately after the click.
#     Selenium has no direct `isConnected` getter; a StaleElementReference
#     error on ANY call against the same resolved WebDriver element handle IS
#     the WebDriver-level equivalent — and critically, checking the ORIGINAL
#     handle (not re-querying the selector) is what makes this trustworthy.
#     Re-querying by selector/id after a body swap would find a fresh node
#     with the same id and wrongly read as "connected".
#   - a browser-clock snapshot of a small Turbo lifecycle log
#     (turbo:before-visit / before-render / render / frame-render / load),
#     taken right before and right after the click, so a body-swap bracketing
#     the click shows up as new log entries appearing between the two reads.
#
# Kept deliberately minimal (a couple of WebDriver round trips per click, no
# synchronous logging/formatting at click time) because heavier instrumentation
# in an earlier pass appeared to change timing enough to mask the flake.
module ClickDiagnostics
  # Page-level Drive events (the brief's original list) PLUS the frame-level
  # fetch/render events — several of the flaky tests click an anchor whose
  # target is a turbo-frame-scoped navigation, not a page-level visit, and the
  # page-level events alone stayed silent for that case (see the report).
  LIFECYCLE_EVENTS = %w[
    turbo:before-visit turbo:before-render turbo:render turbo:load
    turbo:before-fetch-request turbo:before-fetch-response
    turbo:before-frame-render turbo:frame-render turbo:frame-load turbo:frame-missing
  ].freeze

  # Every statement here is semicolon-terminated on purpose: `window.__turboLog
  # = [];` with NO semicolon, followed by a line starting with `[...]`, is a
  # classic ASI trap — JS glues them into one `[]["a","b"]`-style indexing
  # expression instead of two statements, which throws exactly
  # "Cannot read properties of undefined (reading 'forEach')". Hit this while
  # building the harness; it had nothing to do with the flake.
  SNAPSHOT_JS = <<~JS.freeze
    (() => {
      try {
        if (!window.__turboLog) {
          window.__turboLog = [];
          #{LIFECYCLE_EVENTS.inspect}.forEach(function(evt) {
            document.addEventListener(evt, function() {
              window.__turboLog.push([performance.now(), evt, location.pathname]);
            });
          });
        }
        return { t: performance.now(), log: window.__turboLog, active: document.activeElement && document.activeElement.tagName };
      } catch (e) {
        return { jsError: String(e), stack: String(e && e.stack) };
      }
    })()
  JS

  def click(*keys, **options)
    label = describe_self
    before = snapshot
    stale_before = stale?

    error = nil
    begin
      result = super
    rescue StandardError => e
      error = e
    end

    stale_after = stale?
    after = snapshot

    # `.click` returning does NOT mean an async Turbo frame/fetch triggered by
    # it has resolved yet — this "after" snapshot only sees what happened
    # SYNCHRONOUSLY inside the click dispatch. Deliberately NOT adding a sleep
    # here to look further forward: that would insert a fixed delay after
    # EVERY click in the entire suite and is exactly the kind of overhead that
    # appeared to mask the flake before. Instead, on failure, teardown takes
    # one more free look — by the time a test has failed, Capybara's own 5s
    # poll has already elapsed with no instrumentation-added delay, so that
    # snapshot shows what eventually happened at zero timing cost.
    ClickDiagnostics.log << {
      label: label,
      stale_before: stale_before,
      stale_after: stale_after,
      before: before,
      after: after,
      error: error&.message,
      wall_time: Time.now,
    }

    raise error if error

    result
  end

  private

  def describe_self
    "<#{tag_name} id=#{self[:id].inspect} data-turbo-frame=#{self[:"data-turbo-frame"].inspect}>"
  rescue StandardError
    "<unknown>"
  end

  # Any WebDriver call against the SAME resolved element handle raises
  # StaleElementReferenceError once that node leaves the live document — this
  # is the operational definition of `isConnected === false` for a driver that
  # doesn't expose the DOM property directly.
  def stale?
    native.enabled?
    false
  rescue Selenium::WebDriver::Error::StaleElementReferenceError
    true
  rescue StandardError
    nil # not Selenium, or the session itself is gone — don't claim an answer
  end

  def snapshot
    Capybara.current_session.evaluate_script(SNAPSHOT_JS)
  rescue StandardError => e
    { error: e.message }
  end

  class << self
    def log
      $click_diagnostics_log ||= []
    end

    def clear!
      $click_diagnostics_log = []
    end
  end
end

Capybara::Node::Element.prepend(ClickDiagnostics) if ENV["CLICK_DIAGNOSTICS"]
