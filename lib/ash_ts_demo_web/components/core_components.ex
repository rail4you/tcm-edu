defmodule AshTsDemoWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  This is a slimmed-down version of the Phoenix v1.8 generator's
  `core_components.ex` — Gettext and DaisyUI are intentionally omitted so
  the module works in this API-first project. Tailwind utility classes are
  still used for layout; they are no-ops when the assets pipeline has not
  been generated.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash id="welcome-back" kind={:info} phx-mounted={show("#welcome-back")} hidden>
        Welcome Back!
      </.flash>
  """
  attr :id, :string, default: nil
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, include: ~w(phx-click phx-value-key)

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 z-50 rounded-md px-3 py-2 shadow-md text-sm",
        @kind == :info && "bg-blue-100 text-blue-900 border border-blue-200",
        @kind == :error && "bg-red-100 text-red-900 border border-red-200"
      ]}
      {@rest}
    >
      <p :if={@title} class="font-semibold">{@title}</p>
      <p>{msg}</p>
    </div>
    """
  end

  @doc """
  Shows a Heroicon.

  Heroicons are bundled by the assets pipeline; if the assets have not been
  built this just renders an empty span. Use `<.icon name="hero-x-mark" />`.
  """
  attr :name, :string, required: true
  attr :class, :string, default: "w-4 h-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a header with title, optional subtitle, and action slot.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4 border-b border-gray-200"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-gray-500">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a data list with title/value pairs.
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-gray-200">
      <div :for={item <- @item} class="flex justify-between gap-4 py-2 text-sm">
        <dt class="text-gray-500">{item.title}</dt>
        <dd class="text-right font-mono">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a table with generic styling.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true

  slot :col, required: true do
    attr :label, :string
  end

  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full text-sm">
        <thead class="bg-gray-50">
          <tr>
            <th
              :for={col <- @col}
              class="px-3 py-2 text-left font-medium text-gray-600"
            >
              {col[:label]}
            </th>
          </tr>
        </thead>
        <tbody id={@id} class="divide-y divide-gray-100">
          <tr :for={row <- @rows} class="hover:bg-gray-50">
            <td
              :for={col <- @col}
              class="px-3 py-2 align-top font-mono"
            >
              {render_slot(col, row)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  ## JS commands
  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition: {"transition-all ease-out duration-200", "opacity-0", "opacity-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition: {"transition-all ease-in duration-150", "opacity-100", "opacity-0"}
    )
  end
end
