import { Controller } from "@hotwired/stimulus"

// Drives the "Location" dropdown on a card. Debounced search against
// the Mapbox Geocoding API; selecting a result PATCHes the card with
// the chosen lat/lng + label, then re-renders the modal so the preview
// appears. Removing a location is a PATCH that nulls the four fields.
export default class extends Controller {
  static targets = ["input", "results", "empty"]
  static values  = { cardId: Number, cardUrl: String }

  connect() {
    this.token = document.querySelector('meta[name="mapbox-token"]')?.content
    this.activeIndex = -1
    this.lastQuery = ""
    this.debounceTimer = null
  }

  disconnect() {
    clearTimeout(this.debounceTimer)
  }

  search() {
    clearTimeout(this.debounceTimer)
    const q = this.inputTarget.value.trim()
    if (q.length < 2) {
      this.clearResults()
      return
    }
    if (q === this.lastQuery) return
    this.debounceTimer = setTimeout(() => this.fetchResults(q), 250)
  }

  async fetchResults(q) {
    this.lastQuery = q
    if (!this.token) {
      console.warn("Mapbox token missing — set MAPBOX_PUBLIC_TOKEN in .env and restart")
      return
    }

    const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(q)}.json` +
                `?access_token=${this.token}&autocomplete=true&limit=6&language=en`

    try {
      const res = await fetch(url)
      const data = await res.json()
      this.renderResults(data.features || [])
    } catch (e) {
      console.error("Geocoder error:", e)
    }
  }

  renderResults(features) {
    if (features.length === 0) {
      this.resultsTarget.classList.add("hidden")
      this.emptyTarget.classList.remove("hidden")
      return
    }
    this.emptyTarget.classList.add("hidden")
    this.resultsTarget.classList.remove("hidden")

    this.resultsTarget.innerHTML = features.map((f) => {
      const [lng, lat] = f.center
      const name = f.text || f.place_name
      const addr = f.place_name
      return `
        <li class="cursor-pointer hover:bg-blue-50 px-2 py-2 rounded"
            data-action="click->location-search#pick"
            data-lat="${lat}"
            data-lng="${lng}"
            data-name="${this.escape(name)}"
            data-address="${this.escape(addr)}">
          <div class="font-medium text-gray-800 text-sm">${this.escape(name)}</div>
          <div class="text-xs text-gray-500">${this.escape(addr)}</div>
        </li>
      `
    }).join("")
  }

  pick(event) {
    const li = event.currentTarget
    this.persist({
      latitude:         li.dataset.lat,
      longitude:        li.dataset.lng,
      location_name:    li.dataset.name,
      location_address: li.dataset.address
    })
  }

  remove(event) {
    event.preventDefault()
    this.persist({
      latitude:         "",
      longitude:        "",
      location_name:    "",
      location_address: ""
    })
  }

  // PATCH /cards/:id — server returns a turbo_stream that re-renders
  // the modal, which means the static map preview appears (or vanishes
  // on remove) without a manual reload.
  async persist(fields) {
    const formData = new FormData()
    Object.entries(fields).forEach(([k, v]) => formData.append(`card[${k}]`, v))
    formData.append("authenticity_token", this.csrfToken())

    const res = await fetch(this.cardUrlValue, {
      method: "PATCH",
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      body: formData
    })

    if (res.ok) {
      const html = await res.text()
      window.Turbo.renderStreamMessage(html)
    } else {
      console.error("Failed to update card location", res.status)
    }
  }

  clearResults() {
    this.resultsTarget.innerHTML = ""
    this.resultsTarget.classList.add("hidden")
    this.emptyTarget.classList.add("hidden")
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }

  keydown(event) {
    // Stop "Enter" from submitting any enclosing form.
    if (event.key === "Enter") event.preventDefault()
  }
}
