// Phoenix LiveView client entrypoint (bundled by esbuild).
//
//_Served as `/assets/app.js` (see `TcmEduWeb.static_paths/0`)._
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { SidebarCollapse, ThemeController } from "./shell_hooks";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { SidebarCollapse, ThemeController },
});

liveSocket.connect();
window.liveSocket = liveSocket;
