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

Hooks.StateUpdater = {
  mounted() {
    this.handleEvent("control_state_update", (payload) => {
      console.debug("control_state_update", payload)
      let prefix = payload.type === "group" ? "group" : "light"
      let id = payload.id

      let brightness = Number(payload.brightness)
      if (Number.isFinite(brightness)) {
        let input = document.getElementById(`${prefix}-level-${id}`)
        if (input) {
          input.value = brightness
          input.setAttribute("value", brightness)
        } else {
          console.warn("StateUpdater missing brightness input", prefix, id)
        }
        let output = document.getElementById(`${prefix}-brightness-value-${id}`)
        if (output) {
          output.textContent = `${brightness}%`
        } else {
          console.warn("StateUpdater missing brightness output", prefix, id)
        }
      }

      let kelvin = Number(payload.kelvin)
      if (Number.isFinite(kelvin)) {
        let input = document.getElementById(`${prefix}-temp-${id}`)
        if (input) {
          input.value = String(kelvin)
          input.valueAsNumber = kelvin
          input.setAttribute("value", kelvin)
          console.debug("StateUpdater temp", id, input.value, input.valueAsNumber)
        } else {
          console.warn("StateUpdater missing temp input", prefix, id)
        }
        let output = document.getElementById(`${prefix}-temp-value-${id}`)
        if (output) {
          output.textContent = `${kelvin}K`
        } else {
          console.warn("StateUpdater missing temp output", prefix, id)
        }
      }
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

liveSocket.connect()

window.liveSocket = liveSocket
