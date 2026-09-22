defmodule TcmEduWeb.Layouts do
  @moduledoc """
  Layouts for LiveView pages.

  Two shells:

    * `:default` — slim top navbar + centered content (used by `/db`).
    * `:admin` — bare full-viewport slot for the admin dashboard shell
      (`AdminComponents.admin_shell/1` renders its own drawer/navbar).
      Flash messages are still rendered here.

  Every LiveView template must still begin with `<Layouts.app flash={@flash}>`.
  """
  use TcmEduWeb, :html

  # Embed all files in `layouts/*` so `@inner_content` is available inside
  # `root.html.heex`.
  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil, doc: "the current scope (unused for now)"
  attr :shell, :atom, default: :default, values: [:default, :admin, :storefront]

  slot :inner_block, required: true

  def app(%{shell: shell} = assigns) when shell in [:admin, :storefront] do
    ~H"""
    {render_slot(@inner_block)}
    <.flash_group flash={@flash} />
    """
  end

  def app(assigns) do
    ~H"""
    <header class="bg-white border-b border-gray-200 px-4 sm:px-6 lg:px-8">
      <div class="flex h-14 items-center justify-between">
        <div class="flex items-center gap-2">
          <.link navigate={~p"/"} class="font-semibold text-gray-900">
            TCM Education
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
