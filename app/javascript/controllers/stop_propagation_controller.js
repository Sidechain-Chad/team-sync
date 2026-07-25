import { Controller } from "@hotwired/stimulus"

// Stops the event from bubbling. Replaces inline onclick="event.stopPropagation()"
// — e.g. a modal panel that shouldn't trigger a backdrop close-on-click.
export default class extends Controller {
  stop(event) {
    event.stopPropagation()
  }
}
