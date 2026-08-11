# The verified-interaction primitive — built after three tested hypotheses
# failed to localize the system-suite flake (see
# [[project_teamsync_system_test_input_loss]] / CLAUDE.md history): a
# Selenium-driven interaction sometimes produces zero effect, with the
# clicked element never detached and not one Turbo lifecycle event firing —
# not even before the click, in cases where the interaction happens shortly
# after `visit` returns. That points at initialization (Turbo/Stimulus not
# fully wired up yet), not input delivery, but it was never proven — this is
# built to keep measuring that question on every future suite run instead of
# guessing at it once more.
#
# THE RULE THIS EXISTS TO ENFORCE: retries are a last resort for a KNOWN,
# already-diagnosed class of loss, not a way to make flaky tests quietly
# green. A silent retry helper is a machine for converting real app bugs
# into passing tests — the one way this could leave the project worse off
# than the flake it replaces. So:
#
#   - every retry is counted, per interaction, and surfaced in a printed
#     summary at the end of the run — never silent.
#   - a single interaction needing more than RETRY_ALARM_THRESHOLD retries
#     FAILS THE TEST outright, even though the interaction "worked" on a
#     later attempt. Burning through nearly the whole retry budget is itself
#     the signal something is systematically wrong, not something to shrug
#     off because the assertion happened to pass.
#   - every retry captures whether Turbo had started and how many Stimulus
#     controllers were registered at that exact moment — the specific,
#     concrete, testable form of "was the page actually ready" — so retry
#     data becomes a passive experiment on that open question across every
#     future run, not just this one.
module VerifiedInteraction
  # 1 initial attempt + up to 2 retries. Deliberately low — this is meant to
  # absorb a known, narrow class of transient loss, not paper over a
  # genuinely broken interaction, which is exactly why exceeding
  # RETRY_ALARM_THRESHOLD fails the test even on eventual success.
  MAX_ATTEMPTS = 3

  # Needing MORE than one retry (i.e. only succeeding on the 3rd of 3
  # attempts) is the "low threshold" itself — the brief's two constraints
  # ("bounded, a small number of attempts" and "fail if it exceeds a low
  # threshold") collapse to the same number on purpose, rather than two
  # independent knobs that could disagree with each other.
  RETRY_ALARM_THRESHOLD = 1

  READINESS_JS = <<~JS.freeze
    (() => {
      try {
        if (!window.__lastTurboLoadAt) {
          window.__lastTurboLoadAt = performance.now();
          document.addEventListener("turbo:load", function() {
            window.__lastTurboLoadAt = performance.now();
          });
        }
        const turboStarted = typeof window.Turbo !== "undefined" &&
          !!window.Turbo.session && window.Turbo.session.started === true;
        let stimulusCount = null;
        try {
          stimulusCount = window.Stimulus.router.modulesByIdentifier.size;
        } catch (e) { stimulusCount = null; }
        return {
          turboPresent: typeof window.Turbo !== "undefined",
          turboStarted: turboStarted,
          stimulusPresent: typeof window.Stimulus !== "undefined",
          stimulusControllerCount: stimulusCount,
          msSinceLastTurboLoad: performance.now() - window.__lastTurboLoadAt,
        };
      } catch (e) {
        return { jsError: String(e) };
      }
    })()
  JS

  # Number of `*_controller.js` files on disk — the "out of the expected
  # count" denominator. Computed once, not hardcoded, so adding a controller
  # doesn't silently make this stat wrong.
  EXPECTED_STIMULUS_CONTROLLERS = Dir.glob(
    Rails.root.join("app/javascript/controllers/*_controller.js")
  ).size.freeze

  class << self
    def log
      $verified_interaction_log ||= []
    end

    def clear!
      $verified_interaction_log = []
    end

    def print_summary
      return if log.empty?

      total_retries = log.sum { |e| e[:retries] }
      puts "\n=== VERIFIED INTERACTION SUMMARY ==="
      puts "#{log.size} verified interaction(s), #{total_retries} total retries across the run"
      retried = log.select { |e| e[:retries] > 0 }
      if retried.any?
        puts "Interactions that needed a retry (named, not averaged away):"
        retried.each do |e|
          puts "  #{e[:retries]}x retry — #{e[:test]} : #{e[:label]}"
        end
      else
        puts "No interaction needed a retry this run."
      end
      puts "=== end summary ===\n"
    end
  end
end

Minitest.after_run { VerifiedInteraction.print_summary }
