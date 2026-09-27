defmodule TcmEduWeb.AdminAIKeysLive do
  @moduledoc """
  AI Key management at `/admin/ai-keys` (super admins only).

  LiveView replacement for the React `admin/ai-keys` page: keys are stored
  in `TcmEdu.System.ApiKeyConfig` (DB, effective at runtime, no restart).
  Secrets are never rendered back in plaintext.

  表单走 `AshPhoenix.Form.for_create/3`:`ApiKeyConfig.upsert` action 配
  `upsert? true`,表单成功创建或按 provider 更新,无需手写 changeset。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  alias TcmEdu.System.ApiKeyConfig

  on_mount {TcmEduWeb.AdminAuth, :ensure_super_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI Key 管理")
     |> assign(:form, key_form(socket, %{"provider" => "qwen", "is_active" => true}))
     |> assign(:saving, false)
     |> load_keys()}
  end

  @impl true
  def handle_event("validate", %{"key" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"key" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Key 已保存（运行时生效，无需重启）")
         |> assign(
           :form,
           key_form(socket, %{
             "provider" => AshPhoenix.Form.value(form, :provider),
             "is_active" => true
           })
         )
         |> load_keys()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("toggle", %{"provider" => provider}, socket) do
    with config when not is_nil(config) <- find_config(socket, provider),
         {:ok, _} <-
           config
           |> Ash.Changeset.for_update(
             :update,
             %{is_active: !config.is_active},
             actor: actor(socket)
           )
           |> Ash.update() do
      {:noreply, socket |> put_flash(:info, "已更新 #{provider}") |> load_keys()}
    else
      nil -> {:noreply, put_flash(socket, :error, "配置不存在")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("delete", %{"provider" => provider}, socket) do
    case find_config(socket, provider) do
      nil ->
        {:noreply, put_flash(socket, :error, "配置不存在")}

      config ->
        case Ash.destroy(config, actor: actor(socket)) do
          :ok ->
            {:noreply, socket |> put_flash(:info, "已删除 #{provider}") |> load_keys()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}
        end
    end
  end

  defp provider_label("qwen"), do: "通义千问 (Qwen)"
  defp provider_label("dashscope"), do: "DashScope"
  defp provider_label("deepseek"), do: "DeepSeek"
  defp provider_label(other), do: other

  defp provider_options,
    do: [{"通义千问 (Qwen)", "qwen"}, {"DashScope", "dashscope"}, {"DeepSeek", "deepseek"}]

  defp actor(socket), do: socket.assigns.current_admin.actor

  defp find_config(socket, provider) do
    Enum.find(socket.assigns.configs, &(to_string(&1.provider) == provider))
  end

  defp load_keys(socket) do
    configs =
      try do
        ApiKeyConfig.list_api_key_configs!(actor: actor(socket))
        |> Enum.sort_by(&to_string(&1.provider))
      rescue
        _ -> []
      end

    assign(socket, :configs, configs)
  end

  # 走 `:upsert` action(provider 一致时覆盖,否则新建),表单字段来自资源
  # attribute constraints(`one_of: [:qwen, :dashscope, :deepseek]` +
  # `allow_nil? false`),无需手写 validate_inclusion / validate_required。
  defp key_form(socket, params) do
    ApiKeyConfig
    |> AshPhoenix.Form.for_create(:upsert,
      actor: actor(socket),
      as: "key",
      params: params
    )
    |> to_form()
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
