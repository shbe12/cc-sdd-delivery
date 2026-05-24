import { Controller } from "@hotwired/stimulus"

// Adds/removes nested order-item rows in the manager order form.
export default class extends Controller {
  static targets = ["lines", "template"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime().toString())
    this.linesTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const line = event.target.closest("[data-order-form-target='line']")
    const destroyField = line.querySelector("input[name*='_destroy']")
    if (destroyField) {
      destroyField.value = "1"
      line.style.display = "none"
    } else {
      line.remove()
    }
  }
}
