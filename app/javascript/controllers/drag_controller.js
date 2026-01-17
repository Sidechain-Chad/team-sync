import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Connects to data-controller="drag"
export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      group: 'shared', // Allows dragging between different lists!
      animation: 150,
      onEnd: this.end.bind(this)
    })
  }

  end(event) {
    // 1. Identify the card being moved
    const id = event.item.dataset.id

    // 2. Identify the new column (List ID)
    // We access the parent <div> of where the card landed
    // We will need to parse the ID from the DOM (e.g., "list_5_cards" -> 5)
    // For now, let's just log it to prove it works.

    console.log(`Card ${id} moved to new index ${event.newIndex}`)
    console.log(event.to) // The DOM element of the new list
  }
}
