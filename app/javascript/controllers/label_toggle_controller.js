import { Controller } from "@hotwired/stimulus"

// Flips the checkbox visual state instantly on click so the toggle feels
// snappy. The button_to form still submits in the background; the Turbo
// stream response then replaces this frame with the server's canonical
// state, which (in the happy path) matches what we already showed.
export default class extends Controller {
  static targets = ["empty", "checked"]

  toggle() {
    this.emptyTarget.classList.toggle("hidden")
    this.checkedTarget.classList.toggle("hidden")
  }
}
