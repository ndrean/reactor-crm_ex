import { Socket } from "/assets/phoenix.mjs"
import { LiveSocket } from "/assets/phoenix_live_view.esm.js"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {
  CopyToClipboard: {
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
}

let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken }, hooks: Hooks })
liveSocket.connect()
window.liveSocket = liveSocket
