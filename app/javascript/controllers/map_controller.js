import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Renders a single delivery-destination marker on a Mapbox map.
export default class extends Controller {
  static values = { apiKey: String, lat: Number, lng: Number }

  connect() {
    mapboxgl.accessToken = this.apiKeyValue
    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/streets-v12",
      center: [this.lngValue, this.latValue],
      zoom: 14
    })
    new mapboxgl.Marker()
      .setLngLat([this.lngValue, this.latValue])
      .addTo(this.map)
  }

  disconnect() {
    this.map?.remove()
  }
}
