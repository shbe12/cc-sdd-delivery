import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Renders the delivery destination on a polished 3D Mapbox map:
// dusk lighting + atmospheric fog + a branded PizzApp pin + a one-time fly-in.
// Shared by the manager and rider order "show" screens.
export default class extends Controller {
  static values = { apiKey: String, lat: Number, lng: Number }

  connect() {
    if (!this.apiKeyValue) return
    mapboxgl.accessToken = this.apiKeyValue

    const center = [this.lngValue, this.latValue]
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const finalView = { zoom: 15.5, pitch: 60, bearing: -17 }

    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/standard", // 3D buildings + lighting (mapbox-gl v3)
      center,
      // Start wide & flat so we can fly in; under reduced-motion start at the final view.
      zoom: reduceMotion ? finalView.zoom : 13.5,
      pitch: reduceMotion ? finalView.pitch : 0,
      bearing: reduceMotion ? finalView.bearing : 0
    })

    // Standard-style config must be applied after the style finishes loading.
    this.map.on("style.load", () => {
      this.map.setConfigProperty("basemap", "lightPreset", "dusk")
      this.map.setFog({
        range: [1, 12],
        color: "#e6eef8",
        "high-color": "#9ec1ec",
        "horizon-blend": 0.25,
        "space-color": "#0c1330",
        "star-intensity": 0.05
      })
    })

    // One-time cinematic fly-in to the tilted view (skipped under reduced-motion).
    if (!reduceMotion) {
      this.map.on("load", () => {
        this.map.easeTo({ center, ...finalView, duration: 2800 })
      })
    }

    const pin = document.createElement("div")
    pin.className = "order-pin"
    pin.innerHTML =
      '<span class="order-pin__pulse"></span>' +
      '<span class="order-pin__dot"><span class="order-pin__glyph">🍕</span></span>'

    new mapboxgl.Marker({ element: pin, anchor: "bottom" })
      .setLngLat(center)
      .addTo(this.map)
  }

  disconnect() {
    this.map?.remove()
  }
}
