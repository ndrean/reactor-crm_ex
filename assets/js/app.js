import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "./topbar.js"

let Hooks = {}

Hooks.CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      let target = document.getElementById(this.el.dataset.copyTarget)
      if (target) {
        navigator.clipboard.writeText(target.value).then(() => {
          let original = this.el.textContent
          this.el.textContent = "Copié !"
          setTimeout(() => { this.el.textContent = original }, 2000)
        })
      }
    })
  }
}

Hooks.Tippy = {
  mounted() { this.instance = tippy(this.el) },
  updated() {
    this.instance.setProps(
      Object.fromEntries(
        Object.entries(this.el.dataset)
          .filter(([k]) => k.startsWith("tippy"))
          .map(([k, v]) => [this.tippyPropName(k), v])
      )
    )
  },
  destroyed() { this.instance.destroy() },
  tippyPropName(k) {
    const s = k.replace("tippy", "")
    return s.charAt(0).toLowerCase() + s.slice(1)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})


topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
// window.liveSocket = liveSocket