import { Controller } from "@hotwired/stimulus"

// Request-submits the form this controller is attached to, on a triggering
// event (e.g. blur/change). Replaces inline this.form.requestSubmit().
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
