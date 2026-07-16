import { Controller } from "@hotwired/stimulus"

// Repopulates the Position select in the card modal's "Move card" popover
// whenever the List select changes. Options are numeric (1..N), matching
// Trello — the true position is clamped server-side, this just renders a
// sensible range so the client's count is never trusted blindly.
export default class extends Controller {
  static targets = ["listSelect", "positionSelect"]
  static values = { counts: Object, currentListId: Number, currentPosition: Number }

  connect() {
    this.refreshPositions()
  }

  refreshPositions() {
    const listId = parseInt(this.listSelectTarget.value, 10)
    const isCurrentList = listId === this.currentListIdValue
    const activeCount = this.countsValue[listId] || 0
    const max = isCurrentList ? activeCount : activeCount + 1
    const defaultPosition = isCurrentList ? this.currentPositionValue : max

    this.positionSelectTarget.innerHTML = ""
    for (let position = 1; position <= max; position++) {
      const option = document.createElement("option")
      option.value = position
      option.textContent = position
      if (position === defaultPosition) option.selected = true
      this.positionSelectTarget.appendChild(option)
    }
  }
}
