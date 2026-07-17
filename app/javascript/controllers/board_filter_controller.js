import { Controller } from "@hotwired/stimulus"

// Client-side card filtering for the board canvas. No server round-trips,
// no persistence beyond the URL query string — state is read from and
// written to `?filter_due=...&filter_label=...&filter_member=...` so a
// reload or a shared link restores the same view. Semantics: OR within a
// category, AND across categories.
const QUERY_PARAMS = { due: "filter_due", label: "filter_labels", member: "filter_members" }

export default class extends Controller {
  static targets = ["checkbox", "badge", "clearButton", "listCount"]

  connect() {
    // Turbo streams (drag persistence, label edits from the card modal,
    // broadcasts) patch the DOM synchronously inside their own render call.
    // Queuing the re-apply on the next frame guarantees the changed/new
    // card nodes exist before we re-evaluate the active filters.
    this.boundReapply = () => requestAnimationFrame(() => this.apply())
    document.addEventListener("turbo:before-stream-render", this.boundReapply)

    // Belt-and-braces for any plain turbo-frame navigation (not a stream).
    this.boundFrameLoad = () => this.apply()
    document.addEventListener("turbo:frame-load", this.boundFrameLoad)

    // Back/forward restores a cached snapshot of this same page (checkbox
    // DOM state as it was at snapshot time, not necessarily matching the
    // now-current URL) — re-derive checkbox state from the URL on every
    // Turbo visit, including cache restorations, rather than trusting
    // whatever the snapshot happened to have checked.
    this.boundSyncFromURL = () => this.syncFromURL()
    document.addEventListener("turbo:load", this.boundSyncFromURL)

    // The card modal's exit links (Close button, backdrop overlay) live in
    // a separate "modal" turbo-frame (target="_top"), so each is a plain
    // board_path with no query string — closing a card would otherwise
    // silently drop the filter. Rewritten just-in-time, capture phase,
    // before Turbo's own click listener reads the href. Every such link is
    // tagged data-modal-exit (see cards/show.html.erb) rather than matched
    // by aria-label, so this catches every exit path, not just the ✕ button.
    this.boundPreserveFiltersOnClose = this.preserveFiltersOnClose.bind(this)
    document.addEventListener("click", this.boundPreserveFiltersOnClose, true)

    this.syncFromURL()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.boundReapply)
    document.removeEventListener("turbo:frame-load", this.boundFrameLoad)
    document.removeEventListener("turbo:load", this.boundSyncFromURL)
    document.removeEventListener("click", this.boundPreserveFiltersOnClose, true)
  }

  clear() {
    this.checkboxTargets.forEach((checkbox) => (checkbox.checked = false))
    this.apply()
  }

  // Checks the boxes matching the current URL's filter_* params, then
  // applies. Unknown/stale values (e.g. a since-deleted label id) simply
  // never match a checkbox and are dropped silently.
  syncFromURL() {
    const params = new URLSearchParams(window.location.search)
    const wanted = { due: [], label: [], member: [] }
    Object.entries(QUERY_PARAMS).forEach(([category, param]) => {
      const raw = params.get(param)
      if (raw) wanted[category] = raw.split(" ").filter(Boolean)
    })

    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = wanted[checkbox.dataset.category].includes(checkbox.value)
    })

    this.apply()
  }

  apply() {
    const active = { due: [], label: [], member: [] }
    this.checkboxTargets.forEach((checkbox) => {
      if (checkbox.checked) active[checkbox.dataset.category].push(checkbox.value)
    })

    const anyActive = active.due.length > 0 || active.label.length > 0 || active.member.length > 0

    if (this.hasBadgeTarget) this.badgeTarget.classList.toggle("hidden", !anyActive)
    if (this.hasClearButtonTarget) this.clearButtonTarget.disabled = !anyActive

    // Hidden via class toggle, never removed — SortableJS and turbo streams
    // need every card to stay in the DOM. Note: dragging while filtered can
    // produce surprising positions since hidden siblings still occupy
    // positions in the list; that matches Trello's behavior, so it's left
    // as-is rather than special-cased.
    this.element.querySelectorAll("[data-filter-due]").forEach((card) => {
      card.classList.toggle("hidden", !this.cardMatches(card, active))
    })

    this.updateListCounts(anyActive)
    this.updateURL(active)
  }

  // history.replaceState only — this never creates a history entry or
  // triggers a Turbo visit, so toggling a checkbox doesn't pollute
  // back/forward with one step per filter change.
  updateURL(active) {
    const params = new URLSearchParams(window.location.search)
    Object.entries(QUERY_PARAMS).forEach(([category, param]) => {
      if (active[category].length > 0) {
        params.set(param, active[category].join(" "))
      } else {
        params.delete(param)
      }
    })

    const query = params.toString()
    const url = window.location.pathname + (query ? `?${query}` : "")
    history.replaceState(history.state, "", url)
  }

  // See the `boundPreserveFiltersOnClose` listener registered in connect().
  preserveFiltersOnClose(event) {
    const link = event.target.closest("[data-modal-exit]")
    if (!link) return

    const query = window.location.search
    if (!query) return

    const [path] = link.getAttribute("href").split("?")
    link.setAttribute("href", `${path}${query}`)
  }

  cardMatches(card, active) {
    const due = card.dataset.filterDue
    const labels = card.dataset.filterLabels.split(" ").filter(Boolean)
    const members = card.dataset.filterMembers.split(" ").filter(Boolean)

    const dueMatch = active.due.length === 0 || active.due.includes(due)

    const labelMatch =
      active.label.length === 0 ||
      (active.label.includes("none") && labels.length === 0) ||
      labels.some((id) => active.label.includes(id))

    const memberMatch =
      active.member.length === 0 ||
      (active.member.includes("none") && members.length === 0) ||
      members.some((id) => active.member.includes(id))

    return dueMatch && labelMatch && memberMatch
  }

  updateListCounts(anyActive) {
    this.listCountTargets.forEach((el) => {
      el.classList.toggle("hidden", !anyActive)
      if (!anyActive) return

      const container = document.getElementById(`list_${el.dataset.listId}_cards`)
      if (!container) return

      const cards = container.querySelectorAll("[data-filter-due]")
      const visible = Array.from(cards).filter((c) => !c.classList.contains("hidden")).length
      el.textContent = `${visible} of ${cards.length}`
    })
  }
}
