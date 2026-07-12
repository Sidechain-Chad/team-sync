import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { patch } from "@rails/request.js"

export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 250,
      easing: "cubic-bezier(0.2, 0, 0, 1)",
      handle: ".handle", // Only drag when clicking the header
      direction: 'horizontal',
      forceFallback: true,
      fallbackTolerance: 3,
      ghostClass: "list-ghost",
      chosenClass: "list-chosen",
      dragClass: "list-dragging",
      onEnd: this.end.bind(this)
    })
  }

  end(event) {
    const id = event.item.dataset.id
    const newPosition = event.newIndex + 1

    patch(`/lists/${id}/move`, {
      body: JSON.stringify({
        list: { position: newPosition }
      })
    })
  }
}
