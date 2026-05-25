import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Renders a single delivery-destination marker on a Mapbox map.
export default class extends Controller {
  static values = { apiKey: String, lat: Number, lng: Number }

  connect() {
    if (!this.apiKeyValue) return
    mapboxgl.accessToken = this.apiKeyValue
    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/standard", // 3D buildings + lighting (mapbox-gl v3)
      center: [this.lngValue, this.latValue],
      zoom: 15.5, // close enough for 3D buildings to render
      pitch: 60,  // strong tilt to show off the Reforma towers in 3D
      bearing: -17 // slight rotation for depth
    })
    new mapboxgl.Marker()
      .setLngLat([this.lngValue, this.latValue])
      .addTo(this.map)
  }

  disconnect() {
    this.map?.remove()
  }
}
