defmodule TcmEduWeb.AdminAIKeysLive do
  @moduledoc """
  AI Key management at `/admin/ai-keys` (super admins only).

  LiveView replacement for the React `admin/ai-keys` page: keys are stored
  in `TcmEdu.System.ApiKeyConfig` (DB, effective at runtime, no restart).
  Secrets are never rendered back in plaintext.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  alias TcmEdu.System.ApiKeyConfig

  on_mount {TcmEduWeb.AdminAuth, :ensure_super_admin}

  @providers ~w(qwen dashscope deepseek)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI Key 管理")
     |> assign(:form, key_form(%{"provider" => "qwen", "is_active" => true}))
     |> assign(:saving, false)
     |> load_keys()}
  end

  @impl true
  def handle_event("validate", %{"key" => params}, socket) do
    {:noreply, assign(socket, :form, key_form(params))}
  end

  def handle_event("save", %{"key" => params}, socket) do
    changeset = key_changeset(params)

    if changeset.valid? do
      get = &Ecto.Changeset.get_field(changeset, &1)

      attrs = %{
        provider: String.to_existing_atom(get.(:provider)),
        api_key: get.(:api_key) |> to_string() |> String.trim(),
        base_url: empty_to_nil(get.(:base_url)),
        model: empty_to_nil(get.(:model)),
        is_active: get.(:is_active) != false
      }

      case ApiKeyConfig.set_api_key_config(attrs, actor: actor(socket)) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Key 已保存（运行时生效，无需重启）")
           |> assign(:form, key_form(%{"provider" => get.(:provider), "is_active" => true}))
           |> load_keys()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "key"))}
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

  defp key_form(params) do
    params |> key_changeset() |> Phoenix.Component.to_form(as: "key")
  end

  defp key_changeset(params) do
    {%{provider: "qwen", is_active: true},
     %{
       provider: :string,
       api_key: :string,
       base_url: :string,
       model: :string,
       is_active: :boolean
     }}
    |> Ecto.Changeset.cast(params, [:provider, :api_key, :base_url, :model, :is_active])
    |> Ecto.Changeset.validate_required([:provider, :api_key])
    |> Ecto.Changeset.validate_inclusion(:provider, @providers)
    |> Ecto.Changeset.validate_length(:api_key, min: 4, max: 500)
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)
  defp empty_to_nil(value), do: value

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
