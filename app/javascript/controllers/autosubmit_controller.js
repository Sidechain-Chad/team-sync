import { Controller } from "@hotwired/stimulus"

// Request-submits the form this controller is attached to, on a triggering
// event (blur / change / Enter). Replaces inline this.form.requestSubmit().
//
// SINGLE ENTRY POINT. The inline renames used to carry a hidden submit button so
// Enter would submit, and separately bound blur->submit. That meant TWO paths
// into the same write, and pressing Enter fired both: the browser's implicit
// submission, then a blur — because replacing the frame (from the response or
// the broadcast) moves focus off the field. Two writes and two broadcasts per
// keystroke.
//
// An "ignore while a submission is in flight" guard was tried and measured, and
// does NOT work: the two submissions are sequential, not overlapping. The blur
// is *caused by* the first submission's own DOM replacement, which lands on the
// repaint AFTER turbo:submit-end — so the in-flight window has already closed.
// Worse, it's a race whose outcome differs per call site (list rename won it
// most of the time because its ActionCable broadcast beat its HTTP response;
// the broadcast-only card tile always lost). Hence this approach instead:
// Enter comes through submit() like everything else, with preventDefault
// stopping the browser's implicit submission, so there is only ever one path.
//
// Note removing the hidden submit button is NOT on its own enough — per the HTML
// spec a form with a single text field still implicit-submits on Enter. The
// `:prevent` action option on the keydown.enter binding is what actually closes
// that path. (Supported by the Stimulus bundled with stimulus-rails 1.3.4.)
export default class extends Controller {
  // Opt-in, defaulting to OFF, so the checklist-item completion checkbox is
  // completely untouched: it binds change->submit only, fires once per
  // interaction, has no blur binding, and so has no double-submit to fix.
  // Toggling it twice in a row is two legitimate changes and must stay that way.
  // Only the inline renames (list, card tile, card modal) set once.
  static values = { once: { type: Boolean, default: false } }

  connect() {
    this.submitted = false

    // Re-arm after a FAILED submission, so a rejected value can be corrected and
    // resubmitted from the same form instance rather than being locked out until
    // a reload. On success the flag is irrelevant — the frame is replaced, or
    // this instance is going away with it.
    //
    // CAVEAT, see the report: this app deliberately answers validation failures
    // with 200 (Turbo drops a 4xx turbo-stream response for a frame-targeted
    // submission), so detail.success is TRUE for them and this does not fire.
    // It doesn't matter today because every rename failure branch replaces the
    // form with the read-only display partial, so the next attempt gets a fresh
    // instance and a fresh flag. If a failure branch is ever changed to keep the
    // form on screen, re-arm on the field's `input` event instead — status codes
    // can't distinguish this app's failures.
    this.reArmIfFailed = (event) => {
      if (!event.detail.success) this.submitted = false
    }

    this.element.addEventListener("turbo:submit-end", this.reArmIfFailed)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.reArmIfFailed)
  }

  submit() {
    if (this.onceValue) {
      if (this.submitted) return

      this.submitted = true
    }

    this.element.requestSubmit()
  }
}
