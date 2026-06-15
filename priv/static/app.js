// Bootstrap for LiveView in an environment without a JS asset pipeline.
//
// The minified clients in `phoenix.min.js` and `phoenix_live_view.min.js`
// expose `window.Phoenix` and `window.LiveView` as namespaces but do not
// attach to the page on their own. This file wires up a `LiveSocket`
// against the `/live` endpoint, just like the `app.js` shipped with
// `mix phx.new` does.
(function () {
  var csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

  var liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: { _csrf_token: csrfToken },
  });

  liveSocket.connect();
  window.liveSocket = liveSocket;
})();
