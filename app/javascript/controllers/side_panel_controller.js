import { Controller } from "@hotwired/stimulus"

// Manages the left side panel that slides in from the bottom-nav buttons.
// Tracks which panel is currently open ("planner", "inbox", or none) and
// loads the corresponding content into a turbo-frame on demand.
export default class extends Controller {
  static targets = ["panel", "frame", "backdrop"]
  static values  = { open: Boolean, currentPanel: String }

  // Toggle a named panel. If it's already open, close. If a different one
  // is open, swap content. If nothing is open, open it.
  toggle(event) {
    event.preventDefault()
    const button = event.currentTarget
    const panelName = button.dataset.panelName
    const panelUrl  = button.dataset.panelUrl

    if (this.openValue && this.currentPanelValue === panelName) {
      this.close()
    } else {
      this.open(panelName, panelUrl)
    }
  }

  open(panelName, panelUrl) {
    this.currentPanelValue = panelName
    this.openValue = true
    this.panelTarget.classList.remove("-translate-x-full")
    this.backdropTarget.classList.remove("hidden")
    // Setting src triggers Turbo to fetch the panel HTML and render it
    // inside the frame — same pattern as turbo modals.
    this.frameTarget.setAttribute("src", panelUrl)
    this._highlightActiveButton(panelName)
  }

  close() {
    this.openValue = false
    this.currentPanelValue = ""
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
    this._highlightActiveButton(null)
  }

  // Backdrop click closes the panel (matches Trello's behavior).
  closeFromBackdrop(event) {
    if (event.target === this.backdropTarget) this.close()
  }

  _highlightActiveButton(panelName) {
    // Update visual state on the bottom nav buttons. Find buttons with
    // data-panel-name matching the open panel and apply active classes.
    this.element.querySelectorAll("[data-panel-name]").forEach(btn => {
      const isActive = btn.dataset.panelName === panelName
      btn.classList.toggle("bg-white/15", isActive)
      btn.classList.toggle("text-white",  isActive)
    })
  }
}
