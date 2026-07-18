import { Controller } from "@hotwired/stimulus"

// Animates probability bars from zero when a fresh prediction is streamed in.
export default class extends Controller {
  static targets = ["bar", "row"]
  static values = { animate: Boolean }

  connect() {
    if (!this.animateValue) return

    this.barTargets.forEach((bar) => {
      const target = bar.style.width
      bar.style.width = "0%"
      requestAnimationFrame(() => { bar.style.width = target })
    })
  }
}
