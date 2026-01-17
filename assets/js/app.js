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
      clearTimeout(timeout)
      timeout = setTimeout(() => {
        this.pushEvent("set_brightness", { type, id, level })
      }, 200)
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

liveSocket.connect()

window.liveSocket = liveSocket
