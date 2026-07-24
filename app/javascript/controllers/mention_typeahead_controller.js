import { Controller } from "@hotwired/stimulus"

// @mention typeahead for the comment textarea. The candidate list (board
// member display names) is embedded via the members value at render time —
// no fetch, no new endpoint, since the list is small and already visible on
// the board. Selecting a candidate inserts "@Display Name " at the caret;
// the server does the actual mention parsing/notification on save (see
// Comment#mentioned_users) — this controller only edits the textarea text.
export default class extends Controller {
  static targets = ["textarea", "dropdown"]
  static values  = { members: Array }

  connect() {
    this.open = false
    this.filtered = []
    this.activeIndex = 0
    this.mentionStart = null
  }

  disconnect() {
    clearTimeout(this.blurTimer)
  }

  // Fired on the textarea's `input` event. Looks backward from the caret for
  // an "@" that isn't separated from the caret by whitespace — that's the
  // fragment currently being typed for a mention.
  onInput() {
    const caret = this.textareaTarget.selectionStart
    const upToCaret = this.textareaTarget.value.slice(0, caret)
    const atIndex = upToCaret.lastIndexOf("@")

    if (atIndex === -1) return this.close()

    const fragment = upToCaret.slice(atIndex + 1)
    if (/\s/.test(fragment)) return this.close()

    const matches = this.membersValue.filter((name) =>
      name.toLowerCase().startsWith(fragment.toLowerCase())
    )

    if (matches.length === 0) return this.close()

    this.mentionStart = atIndex
    this.filtered = matches
    this.activeIndex = 0
    this.render()
  }

  // Listed BEFORE comment-form's keydown action in the textarea's
  // data-action, so when the dropdown is open we can
  // stopImmediatePropagation and prevent comment-form#submitOnEnter from
  // also firing on the same Enter keypress.
  onKeydown(event) {
    if (!this.open) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        event.stopImmediatePropagation()
        this.activeIndex = (this.activeIndex + 1) % this.filtered.length
        this.render()
        break
      case "ArrowUp":
        event.preventDefault()
        event.stopImmediatePropagation()
        this.activeIndex = (this.activeIndex - 1 + this.filtered.length) % this.filtered.length
        this.render()
        break
      case "Enter":
        event.preventDefault()
        event.stopImmediatePropagation()
        this.select(this.filtered[this.activeIndex])
        break
      case "Escape":
        event.preventDefault()
        event.stopImmediatePropagation()
        this.close()
        break
      case " ":
        // Typing past the mention without picking anything dismisses it.
        this.close()
        break
    }
  }

  pick(event) {
    // A click on a dropdown item blurs the textarea first — cancel the
    // pending blur-close so this click still lands.
    clearTimeout(this.blurTimer)
    this.select(event.currentTarget.dataset.name)
  }

  // Delayed so a click on a dropdown item (see `pick`) gets a chance to
  // cancel this before the dropdown is torn down.
  onBlur() {
    this.blurTimer = setTimeout(() => this.close(), 150)
  }

  select(name) {
    if (!name || this.mentionStart === null) return this.close()

    const textarea = this.textareaTarget
    const value = textarea.value
    const caret = textarea.selectionStart
    const before = value.slice(0, this.mentionStart)
    const after = value.slice(caret)
    const inserted = `@${name} `

    textarea.value = before + inserted + after
    const newCaret = before.length + inserted.length
    textarea.setSelectionRange(newCaret, newCaret)
    textarea.focus()

    this.close()
  }

  render() {
    this.open = true
    this.dropdownTarget.innerHTML = this.filtered.map((name, i) => `
      <li class="px-3 py-2 text-sm rounded cursor-pointer ${i === this.activeIndex ? "bg-brand-100 text-brand-700" : "text-ink-700 hover:bg-surface-200"}"
          data-action="click->mention-typeahead#pick"
          data-name="${this.escape(name)}">${this.escape(name)}</li>
    `).join("")
    this.dropdownTarget.classList.remove("hidden")
  }

  close() {
    this.open = false
    this.filtered = []
    this.mentionStart = null
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden")
      this.dropdownTarget.innerHTML = ""
    }
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
