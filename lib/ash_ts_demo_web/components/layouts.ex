defmodule AshTsDemoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality used by the
  application's LiveView pages.

  The Phoenix v1.8 generator ships a richer `Layouts` module (with theme
  toggle, flash group, etc.) and a DaisyUI-styled `app/1` slot. This
  project is API-first and has no compiled assets yet, so we keep the
  layout minimal but still satisfy the `<Layouts.app flash={@flash}>`
  contract used by LiveView templates.
  """
  use AshTsDemoWeb, :html

  # Embed all files in `layouts/*` so `@inner_content` is available inside
  # `root.html.heex`.
  embed_templates "layouts/*"

  @doc """
  Renders the app shell — a navbar with the application name and a
  centered main content area. Always wrap your LiveView template's inner
  content with this component.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil, doc: "the current scope (unused for now)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="bg-white border-b border-gray-200 px-4 sm:px-6 lg:px-8">
      <div class="flex h-14 items-center justify-between">
        <div class="flex items-center gap-2">
          <.link navigate={~p"/"} class="font-semibold text-gray-900">
            AshTsDemo
          </.link>
          <span class="text-xs text-gray-400">/ LiveView DB inspector</span>
        </div>
        <nav class="flex items-center gap-4 text-sm">
          <.link navigate={~p"/"} class="text-gray-500 hover:text-gray-900">Home</.link>
          <.link navigate={~p"/db"} class="text-gray-500 hover:text-gray-900">DB stats</.link>
        </nav>
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-4xl space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the standard flash group. Wraps two `<.flash>` calls plus, when
  the LiveView is connected, the client/server reconnect indicators.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="contents">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
