import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let Hooks = {}

function bindBufferedSlider(hook, eventName, valueKey, formatter) {
  hook.dragging = false
  hook.localValue = hook.el.value
  hook.localMin = hook.el.min
  hook.localMax = hook.el.max

  let timeout = null

  let syncOutput = (value) => {
    let outputId = hook.el.dataset.outputId
    if (!outputId) return

    let output = document.getElementById(outputId)
    if (output) output.textContent = formatter(value)
  }

  let beginDrag = () => {
    hook.dragging = true
    hook.localValue = hook.el.value
    hook.localMin = hook.el.min
    hook.localMax = hook.el.max
  }

  let endDrag = () => {
    hook.dragging = false
    hook.localValue = hook.el.value
    hook.localMin = hook.el.min
    hook.localMax = hook.el.max
    syncOutput(hook.el.value)
  }

  hook._bufferedSliderCleanup = () => {
    clearTimeout(timeout)
    document.removeEventListener("mouseup", endDrag)
    document.removeEventListener("touchend", endDrag)
  }

  hook.el.addEventListener("mousedown", beginDrag)
  hook.el.addEventListener("touchstart", beginDrag, { passive: true })
  hook.el.addEventListener("change", endDrag)
  hook.el.addEventListener("blur", endDrag)
  document.addEventListener("mouseup", endDrag)
  document.addEventListener("touchend", endDrag, { passive: true })

  hook.el.addEventListener("input", (event) => {
    let { type, id } = hook.el.dataset
    let value = event.target.value

    hook.localValue = value
    hook.localMin = hook.el.min
    hook.localMax = hook.el.max

    syncOutput(value)

    clearTimeout(timeout)
    timeout = setTimeout(() => {
      hook.pushEvent(eventName, { type, id, [valueKey]: value })
    }, 200)
  })

  hook.updated = () => {
    if (hook.dragging) {
      hook.el.min = hook.localMin
      hook.el.max = hook.localMax
      hook.el.value = hook.localValue
      syncOutput(hook.localValue)
    } else {
      hook.localValue = hook.el.value
      hook.localMin = hook.el.min
      hook.localMax = hook.el.max
      syncOutput(hook.el.value)
    }
  }

  hook.destroyed = () => {
    if (hook._bufferedSliderCleanup) hook._bufferedSliderCleanup()
  }
}

Hooks.BrightnessSlider = {
  mounted() {
    bindBufferedSlider(this, "set_brightness", "level", (value) => `${value}%`)
  }
}

Hooks.TempSlider = {
  mounted() {
    bindBufferedSlider(this, "set_color_temp", "kelvin", (value) => `${value}K`)
  }
}

Hooks.GeoLocate = {
  mounted() {
    this.el.addEventListener("click", () => {
      if (!navigator.geolocation) {
        this.pushEvent("geolocation_error", { message: "Geolocation is not supported in this browser." })
        return
      }

      let timezone = null
      try {
        timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || null
      } catch (_error) {
        timezone = null
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.pushEvent("geolocation_success", {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            timezone
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
