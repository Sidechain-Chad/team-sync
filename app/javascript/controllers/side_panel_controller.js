import { Controller } from "@hotwired/stimulus"

// Manages the left side panel triggered by bottom-nav buttons.
// No backdrop — Trello-style split view where panel and board coexist.
// Shifts the <main id="main-content"> element rightward when open so
// board content stays fully visible alongside the panel.
export default class extends Controller {
  static targets = ["panel", "frame"]
  static values  = { open: Boolean, currentPanel: String }

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
    this.frameTarget.setAttribute("src", panelUrl)
    this._shiftContent(true)
    this._highlightActiveButton(panelName)
  }

  close() {
    this.openValue = false
    this.currentPanelValue = ""
    this.panelTarget.classList.add("-translate-x-full")
    this._shiftContent(false)
    this._highlightActiveButton(null)
  }

  // Push the board content right by the panel's width. Done via a class
  // on <main> so the transition lives in CSS/Tailwind and stays smooth.
  _shiftContent(open) {
    const main = document.getElementById("main-content")
    if (!main) return
    main.classList.toggle("pl-[340px]", open)
  }

  _highlightActiveButton(panelName) {
    this.element.querySelectorAll("[data-panel-name]").forEach(btn => {
      const isActive = btn.dataset.panelName === panelName
      btn.classList.toggle("bg-white/15", isActive)
      btn.classList.toggle("text-white",  isActive)
    })
  }
}
