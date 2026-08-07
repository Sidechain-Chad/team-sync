import { Controller } from "@hotwired/stimulus"

// Mapbox GL JS — loaded lazily, from HERE rather than the layout <head>,
// because only two views (boards/map, planner/map) ever mount this
// controller, and the old layout-level <script>/<link> shipped 1.4MB of
// parser-blocking JS to every board, card modal, and settings page that
// never touches a map.
//
// A per-view `content_for :head` was considered and rejected: the layout
// would then differ between a map page and a non-map page, and a HEAD
// difference is exactly what makes Turbo Drive give up on a soft visit and
// fall back to a full page reload on every navigation to or from a map
// page — trading 1.4MB-on-every-page for a full reload on the pages that
// matter most for this feature.
//
// It's a UMD bundle at this URL, not an ES module — `await import()` would
// not give us `mapboxgl` — so this injects a plain <script> and reads the
// global it attaches once the browser fires `load`.
//
// The promise is cached at MODULE scope, not per-instance, for two
// reasons the brief calls out specifically:
//   - two maps on one page would otherwise both inject the script and
//     both wait on their own fetch, doubling the download for no reason.
//   - a Turbo visit between board and map pages does not tear down the JS
//     module registry (that's the whole point of a soft visit), so this
//     variable — and, once resolved, `window.mapboxgl` itself — survives
//     board → map → board → map navigation, and only the FIRST visit to a
//     map page ever pays for the fetch.
const MAPBOX_JS_URL  = "https://api.mapbox.com/mapbox-gl-js/v3.6.0/mapbox-gl.js"
const MAPBOX_CSS_URL = "https://api.mapbox.com/mapbox-gl-js/v3.6.0/mapbox-gl.css"

let mapboxLoadPromise = null

function loadMapboxGl() {
  // Already loaded (a previous mount on this document, or a Turbo revisit
  // that kept the module registry alive) — nothing to inject or wait on.
  if (window.mapboxgl) return Promise.resolve(window.mapboxgl)
  if (mapboxLoadPromise) return mapboxLoadPromise

  mapboxLoadPromise = Promise.all([loadStylesheet(), loadScript()]).then(() => {
    if (!window.mapboxgl) throw new Error("mapboxgl is undefined after the Mapbox script loaded.")
    return window.mapboxgl
  })

  return mapboxLoadPromise
}

function loadStylesheet() {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`link[href="${MAPBOX_CSS_URL}"]`)
    if (existing) {
      // Stylesheets fire `load` even if already cached/parsed by the time
      // a second listener attaches, so this is safe to add unconditionally.
      existing.addEventListener("load", resolve)
      existing.addEventListener("error", () => reject(new Error("Failed to load Mapbox GL CSS.")))
      return
    }

    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = MAPBOX_CSS_URL
    link.addEventListener("load", resolve)
    link.addEventListener("error", () => reject(new Error("Failed to load Mapbox GL CSS.")))
    document.head.appendChild(link)
  })
}

function loadScript() {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${MAPBOX_JS_URL}"]`)
    if (existing) {
      existing.addEventListener("load", resolve)
      existing.addEventListener("error", () => reject(new Error("Failed to load Mapbox GL JS.")))
      return
    }

    const script = document.createElement("script")
    script.src = MAPBOX_JS_URL
    script.addEventListener("load", resolve)
    script.addEventListener("error", () => reject(new Error("Failed to load Mapbox GL JS.")))
    document.head.appendChild(script)
  })
}

export default class extends Controller {
  static targets = ["container", "data"]

  connect() {
    loadMapboxGl()
      .then(() => {
        // The controller can be torn down (Turbo navigating away) while the
        // script is still in flight — don't touch a disconnected target.
        if (!this.element.isConnected) return
        this.initMap()
      })
      .catch((error) => {
        if (!this.element.isConnected) return
        this.showError(error.message)
      })
  }

  showError(msg) {
    this.containerTarget.innerHTML = `
      <div class="h-full flex flex-col items-center justify-center text-danger-fg gap-2 p-8 bg-surface-0 absolute inset-0 z-50">
        <i class="fa-solid fa-circle-xmark text-3xl" aria-hidden="true"></i>
        <p class="text-sm font-bold">Map failed to load.</p>
        <code class="text-xs bg-danger-50 border border-danger-line text-danger-fg p-2 rounded text-center max-w-md">${this.escape(msg)}</code>
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
            ${c.meta ? `<div class="text-xs text-ink-500 mb-0.5">${this.escape(c.meta)}</div>` : ""}
            <div class="font-semibold text-sm text-ink-700 mb-1">${this.escape(c.title)}</div>
            ${c.address ? `<div class="text-xs text-ink-500 mb-2">${this.escape(c.address)}</div>` : ""}
            <a href="${c.url}" data-turbo-frame="modal"
               class="text-xs text-brand-600 hover:text-brand-700 font-medium">Open card &rarr;</a>
          </div>
        `)

        new mapboxgl.Marker({ color: "#BE451A" }) // brand-600 — Mapbox needs a literal color, can't read the CSS token; must be kept in sync by hand with --color-brand-600
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
