import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault() // Stop it from creating a new line
      this.element.form.requestSubmit() // Submit the form
    }
  }
}
