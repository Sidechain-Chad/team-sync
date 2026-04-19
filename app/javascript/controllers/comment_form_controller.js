import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "toolbar", "submitButton"]

  connect() {
    this.reset()
  }

  // Expand when user clicks the text area
  expand() {
    this.inputTarget.rows = 3
    this.toolbarTarget.classList.remove("hidden")
  }

  // Check if we should collapse when clicking elsewhere
  clickOutside(event) {
    // If click is inside the form, do nothing
    if (this.element.contains(event.target)) return

    // If there is text typed, do NOT collapse (prevent data loss)
    if (this.inputTarget.value.trim() !== "") return

    // Otherwise, shrink back
    this.reset()
  }

  reset() {
    this.inputTarget.rows = 1
    this.toolbarTarget.classList.add("hidden")
  }

  // Handle Enter key
  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      // Click the submit button programmatically
      this.submitButtonTarget.click()
      // Reset after a short delay to allow form submission
      setTimeout(() => {
        this.inputTarget.value = ""
        this.reset() // Optional: keeps it collapsed after send
      }, 100)
    }
  }
}
