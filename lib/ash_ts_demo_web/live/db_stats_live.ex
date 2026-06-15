defmodule AshTsDemoWeb.DbStatsLive do
  @moduledoc """
  A simple counter LiveView page at `/db`.
  """

  use AshTsDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Counter")
      |> assign(:count, 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def handle_event("dec", _params, socket) do
    {:noreply, update(socket, :count, &(&1 - 1))}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :count, 0)}
  end
end
