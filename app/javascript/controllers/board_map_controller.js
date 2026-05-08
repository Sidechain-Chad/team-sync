import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "data"]

  connect() {
    try {
      this.initMap()
    } catch (error) {
      this.showError(error.message)
    }
  }

  showError(msg) {
    this.containerTarget.innerHTML = `
      <div class="h-full flex flex-col items-center justify-center text-red-500 gap-2 p-8 bg-white absolute inset-0 z-50">
        <i class="fa-solid fa-circle-xmark text-3xl"></i>
        <p class="text-sm font-bold">Map failed to load.</p>
        <code class="text-xs bg-red-50 p-2 rounded border border-red-200 text-center max-w-md">${msg}</code>
      </div>
    `
  }

  initMap() {
    if (typeof mapboxgl === "undefined") {
      throw new Error("mapboxgl is undefined. The Mapbox JS script didn't load from the network.")
    }

    const token = document.querySelector('meta[name="mapbox-token"]')?.content
    if (!token) {
      throw new Error("MAPBOX_PUBLIC_TOKEN is missing from your .env file or meta tag.")
    }
    
    mapboxgl.accessToken = token
    const cards = JSON.parse(this.dataTarget.textContent)

    // Initialize map safely at a default center
    this.map = new mapboxgl.Map({
      container: this.containerTarget,
      style: "mapbox://styles/mapbox/streets-v12",
      center: [0, 0],
      zoom: 1
    })

    // Catch asynchronous Mapbox errors (like 401 Unauthorized API keys)
    this.map.on('error', (e) => {
      console.error("Mapbox internal error:", e)
      if (e.error && e.error.status === 401) {
         this.showError("Mapbox Token is unauthorized. Check your Mapbox account settings or generate a new default public token.")
      }
    })
    
    this.map.addControl(new mapboxgl.NavigationControl(), "top-right")

    if (cards.length > 0) {
      const bounds = new mapboxgl.LngLatBounds()
      
      cards.forEach(c => {
        bounds.extend([c.lng, c.lat])

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

      // FIX: Check if bounds actually have an area (meaning the cards aren't all in the exact same spot)
      const ne = bounds.getNorthEast()
      const sw = bounds.getSouthWest()
      const hasArea = (ne.lng !== sw.lng) || (ne.lat !== sw.lat)

      if (hasArea) {
        this.map.fitBounds(bounds, { padding: 60, maxZoom: 14, duration: 0 })
      } else {
        // All cards share the exact same location. Just center it.
        this.map.setCenter([sw.lng, sw.lat])
        this.map.setZoom(14)
      }
    }

    // Wait for CSS to fully settle before forcing a canvas resize
    setTimeout(() => {
      if (this.map) this.map.resize()
    }, 150)
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
