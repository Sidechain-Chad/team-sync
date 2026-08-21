import { Controller } from "@hotwired/stimulus"

// Appearance switcher (Light / Dark), mounted in the account
// menu in shared/_top_nav.
//
// The DOM write and the persist are deliberately separate concerns:
//
//   1. Set data-theme on <html> immediately. The whole palette is keyed off
//      that attribute in CSS, so the repaint is synchronous and the menu you
//      are still looking at recolours under the cursor. Waiting for the round
//      trip would make a free change feel like a page load.
//
//   2. Fire the PATCH to persist it. Nothing in the UI waits on the response,
//      because nothing in the UI depends on it — the theme is already applied.
//      The request only decides whether the choice survives a reload.
//
// No Turbo, no reload: a redirect here would throw away the modal, the open
// dropdown, and any unsaved card the user was editing, to achieve a repaint
// that has already happened.
export default class extends Controller {
  static targets = ["option"]
  static values = { url: String }

  select(event) {
    const theme = event.params.theme

    document.documentElement.dataset.theme = theme
    this.#markCurrent(theme)
    this.#persist(theme)
  }

  // The radiogroup keyboard contract: arrow keys move between options and
  // SELECT as they go (that is the pattern for radios, unlike a listbox), Home
  // and End jump to the ends. Without this the role would be a lie — which is
  // exactly why the menuitem* roles are banned app-wide rather than declared
  // and left unimplemented (see DropdownAriaTest).
  navigate(event) {
    const keys = {
      ArrowDown: 1, ArrowRight: 1,
      ArrowUp: -1, ArrowLeft: -1,
    }

    let next
    if (event.key in keys) {
      const from = this.optionTargets.indexOf(event.currentTarget)
      // Wrap, so ArrowUp from the first option lands on the last.
      next = (from + keys[event.key] + this.optionTargets.length) % this.optionTargets.length
    } else if (event.key === "Home") {
      next = 0
    } else if (event.key === "End") {
      next = this.optionTargets.length - 1
    } else {
      return
    }

    // Only now, once we know the key was ours — otherwise Tab, Escape and the
    // dropdown's own key handling would be swallowed.
    event.preventDefault()

    const option = this.optionTargets[next]
    const theme = option.dataset.themeThemeParam

    document.documentElement.dataset.theme = theme
    this.#markCurrent(theme)
    this.#persist(theme)
    option.focus()
  }

  // Move the checkmark, aria-checked and the tab stop together — they are three
  // views of one fact and drifting apart is how a radiogroup ends up with two
  // checked options. The server renders the initial state, so this only has to
  // keep up between the click and the next full page load.
  #markCurrent(theme) {
    this.optionTargets.forEach((option) => {
      const isCurrent = option.dataset.themeThemeParam === theme
      option.setAttribute("aria-checked", isCurrent ? "true" : "false")
      option.setAttribute("tabindex", isCurrent ? "0" : "-1")
      option.querySelector("[data-theme-check]").classList.toggle("invisible", !isCurrent)
    })
  }

  // Fire-and-forget, with one exception: a failure has to be visible. If the
  // save silently failed, the theme would look changed until the next reload
  // silently reverted it — the specific kind of "did that work?" bug this
  // codebase has spent real time on. keepalive so choosing a theme and
  // immediately navigating still persists.
  #persist(theme) {
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "application/json",
      },
      body: JSON.stringify({ theme }),
      keepalive: true,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Theme save failed: ${response.status}`)
      })
      .catch((error) => console.error(error))
  }
}
