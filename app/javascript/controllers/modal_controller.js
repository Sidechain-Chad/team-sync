import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Close when clicking the dark background
    this.element.addEventListener("click", (e) => {
      if (e.target === this.element) {
        this.close()
      }
    })
  }

  close() {
    // Remove the src attribute to empty the frame
    this.element.removeAttribute("src")
    this.element.innerHTML = ""
  }
}
