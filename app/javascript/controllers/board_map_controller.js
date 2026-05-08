import { Controller } from "@hotwired/stimulus"

// Renders the per-board map. Reads card data from a JSON blob in the
// view (not data attributes — cleaner for arrays of objects). On
// Turbo navigation away, properly tears down the map instance to
// avoid leaks.
export default class extends Controller {
  static targets = ["container", "data"]

  connect() {
    if (typeof mapboxgl === "undefined") {
      this.containerTarget.innerHTML = `
        <div class="h-full flex flex-col items-center justify-center text-gray-500 gap-2 p-8">
          <i class="fa-solid fa-triangle-exclamation text-3xl text-amber-500"></i>
          <p class="text-sm font-medium">Map library didn't load.</p>
          <p class="text-xs text-gray-400">Check your network connection or refresh the page.</p>
        </div>
      `
      return
    }

    const token = document.querySelector('meta[name="mapbox-token"]')?.content
    if (!token) {
      this.containerTarget.innerHTML = `
        <div class="h-full flex flex-col items-center justify-center text-gray-500 gap-2 p-8">
          <i class="fa-solid fa-key text-3xl text-amber-500"></i>
          <p class="text-sm font-medium">Mapbox token not configured.</p>
          <p class="text-xs text-gray-400">Set <code class="bg-gray-100 px-1 rounded">MAPBOX_PUBLIC_TOKEN</code> in .env and restart.</p>
        </div>
      `
      return
    }
    mapboxgl.accessToken = token

    const cards = JSON.parse(this.dataTarget.textContent)

    // Fit the initial view to all the markers.
    const bounds = new mapboxgl.LngLatBounds()
    cards.forEach(c => bounds.extend([c.lng, c.lat]))

    this.map = new mapboxgl.Map({
      container: this.containerTarget,
      style: "mapbox://styles/mapbox/streets-v12",
      bounds: bounds,
      fitBoundsOptions: { padding: 60, maxZoom: 14 }
    })
    this.map.addControl(new mapboxgl.NavigationControl(), "top-right")

    cards.forEach(c => {
      const popup = new mapboxgl.Popup({ offset: 18, closeButton: false }).setHTML(`
        <div class="p-1 min-w-[180px]">
          ${c.meta ? `<div class="text-xs text-gray-500 mb-0.5">${this.escape(c.meta)}</div>` : ""}
          <div class="font-semibold text-sm text-gray-800 mb-1">${this.escape(c.title)}</div>
          ${c.address ? `<div class="text-xs text-gray-500 mb-2">${this.escape(c.address)}</div>` : ""}
          <a href="${c.url}" data-turbo-frame="modal"
             class="text-xs text-blue-600 hover:text-blue-800 font-medium">Open card &rarr;</a>
        </div>
      `)

      new mapboxgl.Marker({ color: "#2563eb" })
        .setLngLat([c.lng, c.lat])
        .setPopup(popup)
        .addTo(this.map)
    })
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
