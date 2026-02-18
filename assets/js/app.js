import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let Hooks = {}

Hooks.BrightnessSlider = {
  mounted() {
    let timeout = null
    this.el.addEventListener("input", (event) => {
      let { type, id } = this.el.dataset
      let level = event.target.value
      let outputId = this.el.dataset.outputId
      if (outputId) {
        let output = document.getElementById(outputId)
        if (output) output.textContent = `${level}%`
      }
      clearTimeout(timeout)
      timeout = setTimeout(() => {
        this.pushEvent("set_brightness", { type, id, level })
      }, 200)
    })
  }
}

Hooks.TempSlider = {
  mounted() {
    let timeout = null
    this.el.addEventListener("input", (event) => {
      let { type, id } = this.el.dataset
      let kelvin = event.target.value
      let outputId = this.el.dataset.outputId
      if (outputId) {
        let output = document.getElementById(outputId)
        if (output) output.textContent = `${kelvin}K`
      }
      clearTimeout(timeout)
      timeout = setTimeout(() => {
        this.pushEvent("set_color_temp", { type, id, kelvin })
      }, 200)
    })
  }
}

Hooks.GeoLocate = {
  mounted() {
    this.el.addEventListener("click", () => {
      if (!navigator.geolocation) {
        this.pushEvent("geolocation_error", { message: "Geolocation is not supported in this browser." })
        return
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.pushEvent("geolocation_success", {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude
          })
        },
        (error) => {
          let message = "Unable to fetch location."
          if (error && error.message) message = error.message
          this.pushEvent("geolocation_error", { message })
        },
        {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 300000
        }
      )
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

liveSocket.connect()

window.liveSocket = liveSocket
