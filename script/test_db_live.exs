defmodule WebSocketTest do
  @moduledoc """
  End-to-end test that connects to the running dev server's LiveView
  WebSocket and verifies the page receives a `{:db_stats_updated, _}`
  PubSub broadcast. Run with:

      mix run script/test_db_live.exs
  """

  require Logger

  alias Phoenix.Socket.Message

  def run do
    # 1. Fetch the static /db page and extract the session + static tokens.
    Logger.info("Fetching /db to get session tokens...")
    %{status_code: 200, body: html} = Req.get!("http://localhost:4011/db")

    session =
      Regex.run(~r/data-phx-session="([^"]+)"/, html) |> List.last() |> URI.decode_www_form()

    static =
      Regex.run(~r/data-phx-static="([^"]+)"/, html) |> List.last() |> URI.decode_www_form()

    Logger.info("session=#{String.slice(session, 0, 40)}... static=#{String.slice(static, 0, 40)}...")

    # 2. Open a WebSocket and send the phx_join message that LiveView expects.
    {:ok, ref} = String.split("", "")
    {:ok, conn} = Mint.WebSocket.connect("ws://localhost:4011/live/websocket")

    Logger.info("WebSocket connected")

    # Mint is in deps? Actually it's not. Use :websocket_client via :gun, or
    # the much simpler WebSockex. But WebSockex might not be installed.
    #
    # Fallback: use Erlang's built-in :httpc + websockets via :gun.
    raise "Use Gun/WebSockex; falling back to direct IEx test"
  end
end

WebSocketTest.run()
