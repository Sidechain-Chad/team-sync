import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"

// Wraps a datetime-local-style input with Flatpickr. Lives inside the
// due-date popover's Turbo Frame, which re-renders on every save — connect/
// disconnect run on every open, so the instance must be torn down cleanly.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.picker = flatpickr(this.inputTarget, {
      enableTime: true,
      time_24hr: false,
      dateFormat: "Y-m-d\\TH:i",
      altInput: true,
      altFormat: "M j, Y at h:i K",
      altInputClass: "w-full text-sm border border-gray-300 rounded px-2.5 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 cursor-pointer",
      defaultHour: 9,
      defaultMinute: 0,
      minuteIncrement: 15,
      disableMobile: true,
    })
  }

  disconnect() {
    if (this.picker) this.picker.destroy()
  }

  preset(event) {
    const preset = event.currentTarget.dataset.datepickerPreset
    const date = new Date()

    switch (preset) {
      case "today-5pm":
        date.setHours(17, 0, 0, 0)
        break
      case "tomorrow-9am":
        date.setDate(date.getDate() + 1)
        date.setHours(9, 0, 0, 0)
        break
      case "next-week":
        date.setDate(date.getDate() + 7)
        date.setHours(9, 0, 0, 0)
        break
      default:
        return
    }

    this.picker.setDate(date, true)
  }

  remove() {
    this.picker.clear()
    const checkbox = this.element.querySelector("input[type=checkbox]")
    if (checkbox) checkbox.checked = false
    this.element.requestSubmit()
  }
}
