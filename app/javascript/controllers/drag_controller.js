import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { patch } from "@rails/request.js"

export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      group: 'cards', // This allows dragging between different lists
      draggable: '[data-id]', // excludes the "Add a card" trigger, which has no data-id
      animation: 250,
      easing: "cubic-bezier(0.2, 0, 0, 1)",
      forceFallback: true,
      fallbackTolerance: 3,
      ghostClass: "card-ghost",
      chosenClass: "card-chosen",
      dragClass: "card-dragging",
      scroll: true,
      scrollSensitivity: 60,
      scrollSpeed: 12,
      onEnd: this.end.bind(this)
    })
  }

  end(event) {
    // Dropped back where it started — nothing changed, skip the PATCH.
    if (event.from === event.to && event.oldIndex === event.newIndex) return

    const id = event.item.dataset.id
    // newDraggableIndex counts only elements matching the `draggable` selector
    // above, so the "Add a card" trigger never skews the position math.
    const newPosition = event.newDraggableIndex + 1
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
    }).then((response) => {
      if (!response.ok) {
        console.error(`Failed to move card ${id}: ${response.statusCode}`)
        this.revert(event)
      }
    })
  }

  // Moves the dragged card back to its pre-drag slot in its original list.
  // Sortable has already mutated the DOM optimistically, so on a failed
  // PATCH we undo that move by hand rather than reloading the whole list.
  revert(event) {
    const container = event.from
    const siblings = Array.from(container.querySelectorAll(':scope > [data-id]'))
      .filter((el) => el !== event.item)
    const reference = siblings[event.oldDraggableIndex]

    if (reference) {
      container.insertBefore(event.item, reference)
    } else {
      container.appendChild(event.item)
    }
  }
}
