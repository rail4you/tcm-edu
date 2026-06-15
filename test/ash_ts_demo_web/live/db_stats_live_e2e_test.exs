defmodule AshTsDemoWeb.DbStatsLiveEndToEndTest do
  @moduledoc """
  End-to-end test for the counter LiveView at `/db`. Verifies the full
  LiveView lifecycle (mount, connected render, events) without mocking.
  """

  use AshTsDemoWeb.LiveViewCase

  test "counter increments and decrements in the connected LiveView", %{conn: conn} do
    {:ok, index_live, html} = live(conn, ~p"/db")

    # Initial render shows 0
    assert html =~ "Counter"
    assert html =~ "0"

    # Click +
    render_click(index_live, "inc")
    assert render(index_live) =~ "1"

    # Click + again
    render_click(index_live, "inc")
    assert render(index_live) =~ "2"

    # Click -
    render_click(index_live, "dec")
    assert render(index_live) =~ "1"

    # Click Reset
    render_click(index_live, "reset")
    assert render(index_live) =~ "0"
  end
end
