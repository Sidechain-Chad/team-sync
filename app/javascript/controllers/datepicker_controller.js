import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"

// Wraps a datetime-local-style input with Flatpickr. Lives inside the
// due-date popover's Turbo Frame, which re-renders on every save — connect/
// disconnect run on every open, so the instance must be torn down cleanly.
export default class extends Controller {
  static targets = ["input", "startInput"]

  connect() {
    this.picker = flatpickr(this.inputTarget, this.pickerOptions())

    // Optional second field in the same popover (start date). Gets its own
    // Flatpickr instance — sharing one would fight over altInput.
    if (this.hasStartInputTarget) {
      this.startPicker = flatpickr(this.startInputTarget, this.pickerOptions())
    }
  }

  disconnect() {
    if (this.picker) this.picker.destroy()
    if (this.startPicker) this.startPicker.destroy()
  }

  pickerOptions() {
    return {
      enableTime: true,
      time_24hr: false,
      dateFormat: "Y-m-d\\TH:i",
      altInput: true,
      altFormat: "M j, Y at h:i K",
      altInputClass: "w-full text-sm border border-line rounded px-2.5 py-2 focus:outline-none focus:ring-2 focus:ring-brand-700 cursor-pointer",
      defaultHour: 9,
      defaultMinute: 0,
      minuteIncrement: 15,
      disableMobile: true,
    }
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

  // "Remove" clears the card's dating entirely — both dates, plus the
  // completed checkbox. Clearing only the due date would leave a start-only
  // card, which the Planner (a due-date view) wouldn't show at all.
  remove() {
    this.picker.clear()
    if (this.startPicker) this.startPicker.clear()
    const checkbox = this.element.querySelector("input[type=checkbox]")
    if (checkbox) checkbox.checked = false
    this.element.requestSubmit()
  }

  // Clears just the start date, turning a range back into a single point on
  // the due date. Same clear-then-submit shape as remove().
  clearStart() {
    if (!this.startPicker) return
    this.startPicker.clear()
    this.element.requestSubmit()
  }
}
