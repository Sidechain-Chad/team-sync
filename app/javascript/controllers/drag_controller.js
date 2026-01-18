import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { patch } from "@rails/request.js" // Standard Rails helper for AJAX

export default class extends Controller {
  // ... connect() stays the same ...
  connect() {
    this.sortable = Sortable.create(this.element, {
      group: 'shared',
      animation: 150,
      onEnd: this.end.bind(this)
    })
  }

  end(event) {
    const id = event.item.dataset.id

    // logic to get list_id from the DOM id "list_5_cards"
    // event.to is the list <ul> or <div> the card was dropped into
    const newListId = event.to.id.replace("list_", "").replace("_cards", "")

    // newIndex is 0-based (0, 1, 2), but acts_as_list is 1-based (1, 2, 3)
    const newPosition = event.newIndex + 1

    this.updateCard(id, newPosition, newListId)
  }

  updateCard(id, position, list_id) {
    // We used `data-drag-url-value="/cards/:id/move"` in the HTML
    // Now we replace :id with the actual card ID
    const url = this.element.dataset.dragUrlValue.replace(":id", id)

    // Rails Request JS helper (cleaner than fetch)
    patch(url, {
      body: JSON.stringify({
        card: {
          position: position,
          list_id: list_id
        }
      })
    })
  }
}
