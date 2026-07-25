import { Controller } from "@hotwired/stimulus"

// Bridges the Help dropdown (top nav) to the keyboard shortcuts overlay
// (board canvas) — two different parts of the DOM, so a window CustomEvent
// is the hand-off; keyboard_controller.js listens for it via its own
// data-action (shortcuts:open@window->keyboard#openHelp on the board canvas).
export default class extends Controller {
  open() {
    window.dispatchEvent(new CustomEvent("shortcuts:open"))
  }
}
