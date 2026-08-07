import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

// Trello-style "insert a card at this exact gap" affordance. Architecture
// note (see claude-code-card-inserter-brief.md): the hover bar is ONE
// absolutely-positioned element per list (the `inserter` target below),
// never a sibling strip between cards — it's excluded from SortableJS's
// `draggable: '[data-id]'` filter and from this controller's own gap math
// by simply never having a `data-id`, the same trick the "Add a card"
// trigger already uses. The composer form IS inserted into the card flow
// temporarily, but it also carries no `data-id`, so it's inert to Sortable
// too.
const SHOW_DELAY = 500
// Short: this fires on every mousemove where the cursor has left the shown
// gap's zone — including moving straight onto the card above or below it,
// not just leaving the list entirely — so it only needs to cover the
// reaction time to reach the + button, not a lingering grace period.
const HIDE_DELAY = 75
// Card gap is 12px (list container's space-y-3) — the zone is proportional
// to that, same ratio as before (zone == full gap on each side).
const EDGE_ZONE = 12 // px around a card's top edge that counts as "the gap"

export default class extends Controller {
  static targets = ["inserter"]
  static values = { listId: Number, createUrl: String }

  connect() {
    this.dragging = false
    this.composerOpen = false
    this.activeGap = null
    this.showTimer = null
    this.hideTimer = null
    this.currentComposer = null

    this.boundMove = this.onMouseMove.bind(this)
    this.boundLeave = this.onMouseLeave.bind(this)
    this.boundDragStart = this.onDragStart.bind(this)
    this.boundDragEnd = this.onDragEnd.bind(this)
    this.boundBeforeStreamRender = this.onBeforeStreamRender.bind(this)

    this.element.addEventListener("mousemove", this.boundMove)
    this.element.addEventListener("mouseleave", this.boundLeave)
    document.addEventListener("cards:drag-start", this.boundDragStart)
    document.addEventListener("cards:drag-end", this.boundDragEnd)
    document.addEventListener("turbo:before-stream-render", this.boundBeforeStreamRender)
  }

  disconnect() {
    this.element.removeEventListener("mousemove", this.boundMove)
    this.element.removeEventListener("mouseleave", this.boundLeave)
    document.removeEventListener("cards:drag-start", this.boundDragStart)
    document.removeEventListener("cards:drag-end", this.boundDragEnd)
    document.removeEventListener("turbo:before-stream-render", this.boundBeforeStreamRender)
    clearTimeout(this.showTimer)
    clearTimeout(this.hideTimer)
  }

  onDragStart() {
    this.dragging = true
    this.cancelPendingShow()
    this.cancelPendingHide()
    this.hideInserterNow()
  }

  onDragEnd() {
    this.dragging = false
  }

  // Defensive cleanup: if a turbo-stream is about to render (a broadcast,
  // or this same client's own drag persistence) while a gap composer is
  // open in this list, drop it rather than risk an orphaned reference to
  // a form that's about to be replaced out from under it.
  onBeforeStreamRender() {
    if (this.currentComposer) this.closeComposer(this.currentComposer)
  }

  onMouseMove(event) {
    if (this.dragging || this.composerOpen) return

    const gap = this.findGap(event.clientY)

    if (!gap) {
      this.scheduleHide()
      return
    }

    this.cancelPendingHide()
    this.positionInserter(gap)

    if (this.activeGap && this.activeGap.belowId === gap.belowId) return

    this.cancelPendingShow()
    this.activeGap = gap
    this.showTimer = setTimeout(() => this.showInserter(), SHOW_DELAY)
  }

  onMouseLeave() {
    this.scheduleHide()
  }

  insertHere(event) {
    event.preventDefault()
    if (!this.activeGap || this.composerOpen) return

    const gap = this.activeGap
    this.cancelPendingShow()
    this.cancelPendingHide()
    this.hideInserterNow()
    this.openComposer(gap)
  }

  // --- hover timing ---

  scheduleHide() {
    this.cancelPendingShow()
    if (this.hideTimer) return
    this.hideTimer = setTimeout(() => this.hideInserterNow(), HIDE_DELAY)
  }

  cancelPendingShow() {
    clearTimeout(this.showTimer)
    this.showTimer = null
  }

  cancelPendingHide() {
    clearTimeout(this.hideTimer)
    this.hideTimer = null
  }

  showInserter() {
    if (!this.hasInserterTarget || !this.activeGap) return
    this.inserterTarget.classList.remove("hidden")
  }

  hideInserterNow() {
    this.activeGap = null
    if (this.hasInserterTarget) this.inserterTarget.classList.add("hidden")
  }

  // Places the inserter at the vertical midpoint between the below-card's
  // top edge and whatever's above it (the previous visible card's bottom
  // edge, or the container's own content-box top for the first card) —
  // not at the card's top edge itself, which reads as overlapping the
  // card rather than floating in the gap.
  positionInserter(gap) {
    if (!this.hasInserterTarget) return
    const containerRect = this.element.getBoundingClientRect()
    const top = gap.clientMid - containerRect.top + this.element.scrollTop
    this.inserterTarget.style.top = `${top}px`
  }

  // --- gap detection ---

  findGap(clientY) {
    const cards = this.realCards()
    for (let i = 0; i < cards.length; i++) {
      const card = cards[i]
      const rect = card.getBoundingClientRect()
      if (Math.abs(clientY - rect.top) <= EDGE_ZONE) {
        const prevBottom = i > 0 ? cards[i - 1].getBoundingClientRect().bottom : this.contentTop()
        return {
          belowId: card.dataset.id,
          belowPosition: card.dataset.position,
          refEl: card,
          clientMid: (rect.top + prevBottom) / 2
        }
      }
    }
    return null
  }

  // The container's own content-box top edge, in viewport coordinates —
  // stands in for "the previous card's bottom" when there is no previous
  // card, so the above-first-card gap centers the same way every other
  // gap does.
  contentTop() {
    const rect = this.element.getBoundingClientRect()
    const paddingTop = parseFloat(getComputedStyle(this.element).paddingTop) || 0
    return rect.top + paddingTop
  }

  // Real, visible cards only — matches Sortable's own `draggable: '[data-id]'`
  // filter (so the "Add a card" trigger and the gap composer, neither of
  // which have a data-id, are automatically excluded) and additionally
  // skips anything board_filter_controller.js has hidden, since a hidden
  // card occupies no visual gap to hover into.
  realCards() {
    return Array.from(this.element.querySelectorAll(":scope > [data-id]")).filter((el) => {
      const filterEl = el.querySelector("[data-filter-due]")
      return !filterEl || !filterEl.classList.contains("hidden")
    })
  }

  // --- composer ---

  openComposer(gap) {
    this.composerOpen = true

    const composer = document.createElement("div")
    composer.className = "bg-surface-0 p-2 rounded shadow-sm border-2 border-brand-700"
    composer.innerHTML = `
      <div class="space-y-2">
        <textarea class="w-full border-line rounded text-sm focus:ring-brand-700 focus:border-brand-700 p-2"
                  rows="2" placeholder="Enter a title..." required></textarea>
        <div class="flex items-center justify-between">
          <button type="button" data-role="submit" class="bg-brand-600 text-white px-3 py-1 rounded text-xs hover:bg-brand-700 cursor-pointer">Add card</button>
          <button type="button" data-role="cancel" aria-label="Cancel" class="text-xs text-ink-500 hover:text-ink-700 cursor-pointer">&times;</button>
        </div>
      </div>
    `

    if (gap.refEl && gap.refEl.isConnected) {
      this.element.insertBefore(composer, gap.refEl)
    } else {
      this.element.prepend(composer)
    }

    const textarea = composer.querySelector("textarea")
    const submit = () => this.submitComposer(composer, gap, textarea)
    const cancel = () => this.closeComposer(composer)

    composer.querySelector('[data-role="cancel"]').addEventListener("click", cancel)
    composer.querySelector('[data-role="submit"]').addEventListener("click", submit)
    textarea.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.preventDefault()
        cancel()
      } else if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        submit()
      }
    })

    this.currentComposer = composer
    textarea.focus()
  }

  closeComposer(composer) {
    composer.remove()
    this.composerOpen = false
    if (this.currentComposer === composer) this.currentComposer = null
  }

  submitComposer(composer, gap, textarea) {
    const title = textarea.value.trim()
    if (!title) {
      textarea.focus()
      return
    }

    // The response is a no-op (head :ok) — the created card reaches every
    // viewer, including this one, via the board's turbo_stream_from
    // broadcast (see CardsController#create), so there's nothing to
    // render from this request directly.
    post(this.createUrlValue, {
      body: JSON.stringify({ card: { title: title, position: gap.belowPosition } }),
      responseKind: "turbo-stream"
    }).then((response) => {
      if (!response.ok) console.error(`Failed to create card at position ${gap.belowPosition}`)
    })

    this.closeComposer(composer)
  }
}
