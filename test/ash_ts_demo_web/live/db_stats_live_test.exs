defmodule AshTsDemoWeb.DbStatsLiveTest do
  use AshTsDemoWeb.LiveViewCase

  test "renders the counter with initial value 0", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/db")

    assert html =~ "Counter"
    assert html =~ "0"
  end

  test "increment and decrement update the displayed count", %{conn: conn} do
    {:ok, index_live, _html} = live(conn, ~p"/db")

    html = render_click(index_live, "inc")
    assert html =~ "1"

    html = render_click(index_live, "inc")
    assert html =~ "2"

    html = render_click(index_live, "dec")
    assert html =~ "1"
  end

  test "reset sets the count back to 0", %{conn: conn} do
    {:ok, index_live, _html} = live(conn, ~p"/db")

    render_click(index_live, "inc")
    render_click(index_live, "inc")
    render_click(index_live, "inc")

    html = render_click(index_live, "reset")
    assert html =~ "0"
  end
end
