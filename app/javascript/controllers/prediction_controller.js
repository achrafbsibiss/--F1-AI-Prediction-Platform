import { Controller } from "@hotwired/stimulus"

// Grows the probability bars from zero so a streamed-in prediction reads as a
// change rather than a silent swap. Skipped when the visitor prefers reduced motion.
export default class extends Controller {
  static targets = ["bar"]

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.barTargets.forEach((bar) => {
      const width = bar.style.width
      bar.style.width = "0%"
      requestAnimationFrame(() => { bar.style.width = width })
    })
  }
}
