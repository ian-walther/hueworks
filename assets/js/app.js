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

function bindBufferedColorSlider(hook, formatter) {
  hook.dragging = false
  hook.localValue = hook.el.value

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
  }

  let endDrag = () => {
    hook.dragging = false
    hook.localValue = hook.el.value
    syncOutput(hook.el.value)
  }

  let currentColorValues = () => {
    let hueInput = document.getElementById(hook.el.dataset.hueInputId)
    let saturationInput = document.getElementById(hook.el.dataset.saturationInputId)

    return {
      hue: hueInput ? hueInput.value : null,
      saturation: saturationInput ? saturationInput.value : null
    }
  }

  hook._bufferedColorSliderCleanup = () => {
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
    syncOutput(value)

    clearTimeout(timeout)
    timeout = setTimeout(() => {
      let { hue, saturation } = currentColorValues()
      hook.pushEvent("set_color", { type, id, hue, saturation })
    }, 200)
  })

  hook.updated = () => {
    if (hook.dragging) {
      hook.el.value = hook.localValue
      syncOutput(hook.localValue)
    } else {
      hook.localValue = hook.el.value
      syncOutput(hook.el.value)
    }
  }

  hook.destroyed = () => {
    if (hook._bufferedColorSliderCleanup) hook._bufferedColorSliderCleanup()
  }
}

Hooks.ColorHueSlider = {
  mounted() {
    bindBufferedColorSlider(this, (value) => `${value}°`)
  }
}

Hooks.ColorSaturationSlider = {
  mounted() {
    bindBufferedColorSlider(this, (value) => `${value}%`)
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

Hooks.CircadianChart = {
  mounted() {
    this.svg = null
    this.crosshair = null
    this.focusDot = null
    this.tooltip = null

    this.hide = () => {
      if (this.crosshair) this.crosshair.style.opacity = "0"
      if (this.focusDot) this.focusDot.style.opacity = "0"
      if (this.tooltip) this.tooltip.style.opacity = "0"
    }

    this.handleMouseMove = (event) => this.updateFromClientX(event.clientX)
    this.handleTouchMove = (event) => {
      if (event.touches && event.touches[0]) {
        this.updateFromClientX(event.touches[0].clientX)
      }
    }

    this.bindSvg = (svg) => {
      if (!svg) return
      svg.addEventListener("mousemove", this.handleMouseMove)
      svg.addEventListener("mouseleave", this.hide)
      svg.addEventListener("touchmove", this.handleTouchMove, { passive: true })
      svg.addEventListener("touchend", this.hide, { passive: true })
    }

    this.unbindSvg = (svg) => {
      if (!svg) return
      svg.removeEventListener("mousemove", this.handleMouseMove)
      svg.removeEventListener("mouseleave", this.hide)
      svg.removeEventListener("touchmove", this.handleTouchMove)
      svg.removeEventListener("touchend", this.hide)
    }

    this.refreshElements = () => {
      let nextSvg = this.el.querySelector("svg")

      if (this.svg !== nextSvg) {
        this.unbindSvg(this.svg)
        this.svg = nextSvg
        this.bindSvg(this.svg)
      }

      this.crosshair = this.el.querySelector("[data-role='crosshair']")
      this.focusDot = this.el.querySelector("[data-role='focus-dot']")
      this.tooltip = this.el.querySelector("[data-role='tooltip']")
    }

    this.syncData = () => {
      this.refreshElements()

      try {
        this.points = JSON.parse(this.el.dataset.points || "[]")
      } catch (_error) {
        this.points = []
      }

      this.viewBox = this.svg?.viewBox?.baseVal || { width: 760, height: 240 }
      this.hide()
    }

    this.updateFromClientX = (clientX) => {
      if (!this.svg || !this.points || this.points.length === 0) return

      let svgRect = this.svg.getBoundingClientRect()
      if (!svgRect.width) return

      let svgX = ((clientX - svgRect.left) / svgRect.width) * this.viewBox.width
      let nearestPoint = this.points.reduce((best, point) => {
        if (!best) return point
        return Math.abs(point.x - svgX) < Math.abs(best.x - svgX) ? point : best
      }, null)

      if (!nearestPoint) return

      if (this.crosshair) {
        this.crosshair.setAttribute("x1", nearestPoint.x)
        this.crosshair.setAttribute("x2", nearestPoint.x)
        this.crosshair.style.opacity = "1"
      }

      if (this.focusDot) {
        this.focusDot.setAttribute("cx", nearestPoint.x)
        this.focusDot.setAttribute("cy", nearestPoint.y)
        this.focusDot.style.opacity = "1"
      }

      if (this.tooltip) {
        this.tooltip.innerHTML = `<strong>${nearestPoint.time_label}</strong><span>${nearestPoint.value_label}</span>`

        let wrapperRect = this.el.getBoundingClientRect()
        let left = (svgRect.left - wrapperRect.left) + (nearestPoint.x / this.viewBox.width) * svgRect.width
        let top = (svgRect.top - wrapperRect.top) + (nearestPoint.y / this.viewBox.height) * svgRect.height
        let minLeft = 72
        let maxLeft = Math.max(wrapperRect.width - 72, minLeft)
        let clampedLeft = Math.max(minLeft, Math.min(maxLeft, left))

        this.tooltip.style.left = `${clampedLeft}px`
        this.tooltip.style.top = `${Math.max(top - 10, 20)}px`
        this.tooltip.style.opacity = "1"
      }
    }

    this.syncData()
  },

  updated() {
    this.syncData()
  },

  destroyed() {
    this.unbindSvg(this.svg)
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

liveSocket.connect()

window.liveSocket = liveSocket
