import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "trigger"]

  // The keydown listener is bound to THIS element, not the document, and that
  // placement is the whole design. keyboard_controller.js already owns a
  // document-level Esc chain (help overlay → filter popover → card modal);
  // two document-level listeners would race on registration order, which is
  // DOM order, which is not something a view author should have to reason
  // about. Listening on the element means Esc only reaches us when focus is
  // inside this dropdown, and stopPropagation() then keeps the same keystroke
  // from bubbling on to the document chain — so Esc inside a popover opened
  // from the card modal closes the popover and leaves the modal alone.
  connect() {
    this.boundEscape = this.escape.bind(this)
    this.element.addEventListener("keydown", this.boundEscape)
    this.syncExpanded()
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.boundEscape)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const willOpen = this.menuTarget.classList.contains("hidden")

    if (willOpen) {
      this.closeOtherDropdowns()
      this.closeOpenDescriptionEditor()
    }

    this.menuTarget.classList.toggle("hidden")
    this.syncExpanded()
  }

  // Used by inputs (e.g. the top-nav search) where calling toggle() would
  // preventDefault on the focus event and stop the input from focusing.
  // No preventDefault here, and no toggle behaviour — only opens. Closing
  // still happens via the document-level hide() listener.
  open() {
    if (!this.menuTarget.classList.contains("hidden")) return
    this.closeOtherDropdowns()
    this.closeOpenDescriptionEditor()
    this.menuTarget.classList.remove("hidden")
    this.syncExpanded()
  }

  // Unconditional close. Used when something inside the dropdown is
  // clicked but doesn't trigger a full page navigation (e.g. a search
  // result that opens a card in the modal turbo-frame).
  close() {
    this.menuTarget.classList.add("hidden")
    this.syncExpanded()
  }

  hide(event) {
    if (this.element.contains(event.target)) return
    this.menuTarget.classList.add("hidden")
    this.syncExpanded()
  }

  // Esc closes the open dropdown and puts focus back on the trigger —
  // without that last part a keyboard user is dumped at the top of the
  // document. Click-outside (hide) deliberately does NOT move focus: the
  // pointer already put focus wherever the user clicked.
  escape(event) {
    if (event.key !== "Escape") return
    if (this.menuTarget.classList.contains("hidden")) return

    event.preventDefault()
    event.stopPropagation()

    this.menuTarget.classList.add("hidden")
    this.syncExpanded()
    if (this.hasTriggerTarget) this.triggerTarget.focus()
  }

  // aria-expanded has to be updated on EVERY path that shows or hides the
  // menu — toggle, open, close, hide, escape, and the cross-dropdown close
  // below. A stale "true" on a closed menu is worse than no attribute at all,
  // so this is one helper rather than six inline setAttribute calls.
  syncExpanded() {
    if (!this.hasTriggerTarget) return
    const open = !this.menuTarget.classList.contains("hidden")
    this.triggerTarget.setAttribute("aria-expanded", open ? "true" : "false")
  }

  closeOtherDropdowns() {
    document.querySelectorAll('[data-controller~="dropdown"]').forEach((el) => {
      if (el === this.element) return
      const menu = el.querySelector('[data-dropdown-target="menu"]')
      if (menu) menu.classList.add("hidden")
      // Reach for the other dropdown's trigger directly rather than its
      // controller instance: this already manipulates its menu the same way,
      // and going through the application registry for one attribute would be
      // the only place in this file that needs it.
      const trigger = el.querySelector('[data-dropdown-target="trigger"]')
      if (trigger) trigger.setAttribute("aria-expanded", "false")
    })
  }

  // If the description is currently in edit mode, click its Cancel link
  // so the TipTap editor collapses back to read mode. Mirrors Trello —
  // opening a popover discards an in-progress description edit.
  closeOpenDescriptionEditor() {
    const editor = document.querySelector('[data-controller~="tiptap"]')
    if (!editor) return
    const cancelLink = editor.closest('turbo-frame')?.querySelector('a[href*="/cards/"]')
    if (cancelLink) cancelLink.click()
  }
}
