import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { patch } from "@rails/request.js"

export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".handle", // Only drag when clicking the header
      direction: 'horizontal',
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
