import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { patch } from "@rails/request.js"

export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      group: 'cards', // This allows dragging between different lists
      animation: 150,
      onEnd: this.end.bind(this)
    })
  }

  end(event) {
    const id = event.item.dataset.id
    const newPosition = event.newIndex + 1
    const newListId = event.to.dataset.listId

    // This gets the URL from the HTML data attribute
    const url = this.element.dataset.dragUrlValue.replace(":id", id)

    patch(url, {
      body: JSON.stringify({
        card: {
          position: newPosition,
          list_id: newListId
        }
      })
    })
  }
}
