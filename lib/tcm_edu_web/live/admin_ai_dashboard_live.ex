defmodule TcmEduWeb.AdminAIDashboardLive do
  @moduledoc """
  AI cockpit at `/admin/ai-dashboard` (super admins only).

  LiveView replacement for the React `admin/ai-dashboard` page: shows
  configured AI providers, default models from `TcmEdu.AI`, and platform
  activity (recent audit logs) as a health signal.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  require Ash.Query

  alias TcmEdu.System.ApiKeyConfig
  alias TcmEdu.System.AuditLog

  on_mount {TcmEduWeb.AdminAuth, :ensure_super_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI 驾驶舱")
     |> load_dashboard()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_dashboard(socket)}
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, default: "hero-chart-bar"

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body gap-2.5 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">{@title}</p>
          <span class="flex size-12 items-center justify-center rounded-full bg-base-200">
            <.icon name={@icon} class="size-5" />
          </span>
        </div>
        <p class="text-3xl font-semibold tabular-nums">{@value}</p>
        <p :if={@hint} class="text-xs text-base-content/60">{@hint}</p>
      </div>
    </div>
    """
  end

  defp provider_label(:qwen), do: "通义千问 (Qwen)"
  defp provider_label(:dashscope), do: "DashScope"
  defp provider_label(:deepseek), do: "DeepSeek"
  defp provider_label(other), do: to_string(other)

  defp actor(socket), do: socket.assigns.current_admin.actor

  defp load_dashboard(socket) do
    actor = actor(socket)

    configs =
      try do
        ApiKeyConfig.list_api_key_configs!(actor: actor)
        |> Enum.sort_by(&to_string(&1.provider))
      rescue
        _ -> []
      end

    recent_logs =
      try do
        AuditLog
        |> Ash.Query.for_read(:read, %{}, actor: actor)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(8)
        |> Ash.read!()
      rescue
        _ -> []
      end

    active = Enum.count(configs, & &1.is_active)

    assign(socket,
      configs: configs,
      recent_logs: recent_logs,
      stats: %{
        providers: length(configs),
        active: active,
        inactive: length(configs) - active,
        text_model: TcmEdu.AI.text_model(),
        image_model: TcmEdu.AI.image_model()
      }
    )
  end
end
