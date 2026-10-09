defmodule TcmEduWeb.AdminAccountLive do
  @moduledoc """
  管理端账户设置页 `/admin/account`。

  超级管理员与租户管理员均可访问，用于查看/修改自己的资料、头像与密码：

    * 超级管理员（`SuperAdmin`）资料与密码存在 `public.super_admins`，
      通过 `update_profile` / `change_password` action 更新；
    * 租户管理员（`User.role == :tenant_admin`）走租户内 `User` 资源，
      需要带上 `tenant`；头像走 AshStorage（`has_one_attached :avatar`）。

  表单统一走 `AshPhoenix.Form`，头像上传与表单解耦（`TcmEduWeb.UserAvatar`）。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1, role_label: 1, admin_initial: 1]

  alias TcmEduWeb.UserAvatar

  on_mount {TcmEduWeb.AdminAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_admin

    {:ok,
     socket
     |> assign(:page_title, "账户设置")
     |> assign(:profile_form, profile_form(admin, %{}))
     |> assign(:password_form, password_form(admin, %{}))
     |> assign(:avatar_url, load_avatar_url(admin))
     |> UserAvatar.allow_avatar_upload()}
  end

  @impl true
  def handle_event("validate-profile", %{"profile" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :profile_form,
       AshPhoenix.Form.validate(socket.assigns.profile_form, params)
     )}
  end

  def handle_event("save-profile", %{"profile" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.profile_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, actor} ->
        case consume_avatar(socket, actor) do
          {:error, message} ->
            {:noreply, socket |> assign(:profile_form, form) |> put_flash(:error, message)}

          :ok ->
            admin = refresh_admin(socket.assigns.current_admin, actor)

            {:noreply,
             socket
             |> assign(:profile_form, profile_form(admin, %{}))
             |> assign(:avatar_url, load_avatar_url(admin))
             |> assign(:current_admin, admin)
             |> put_flash(:info, "个人资料已更新")}
        end

      {:error, form} ->
        {:noreply, assign(socket, :profile_form, form)}
    end
  end

  def handle_event("remove-avatar", _params, socket) do
    admin = socket.assigns.current_admin

    case UserAvatar.remove_avatar(admin.actor, admin) do
      :ok ->
        admin = refresh_admin(admin, admin.actor)

        {:noreply,
         socket
         |> assign(:avatar_url, load_avatar_url(admin))
         |> assign(:current_admin, admin)
         |> put_flash(:info, "头像已移除")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("validate-password", %{"password" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :password_form,
       AshPhoenix.Form.validate(socket.assigns.password_form, params)
     )}
  end

  def handle_event("save-password", %{"password" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.password_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _actor} ->
        {:noreply,
         socket
         |> assign(:password_form, password_form(socket.assigns.current_admin, %{}))
         |> put_flash(:info, "密码已更新，请使用新密码登录")}

      {:error, form} ->
        {:noreply, assign(socket, :password_form, form)}
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp consume_avatar(socket, actor) do
    if socket.assigns.current_admin.role == "super_admin" do
      :ok
    else
      case UserAvatar.consume_avatar(socket, actor, socket.assigns.current_admin) do
        {:error, message} -> {:error, message}
        _ok -> :ok
      end
    end
  end

  defp refresh_admin(%{role: "super_admin"} = admin, actor) do
    Map.merge(admin, %{actor: actor, name: actor.name || actor.email})
  end

  defp refresh_admin(admin, actor) do
    actor =
      case Ash.load(actor, :avatar_url, actor: admin.actor, tenant: admin.tenant) do
        {:ok, loaded} -> loaded
        _ -> actor
      end

    name = actor.full_name || actor.name || actor.email
    avatar = if is_binary(actor.avatar_url), do: actor.avatar_url, else: nil

    Map.merge(admin, %{
      actor: actor,
      name: name,
      full_name: actor.full_name,
      avatar_url: avatar
    })
  end

  defp load_avatar_url(%{role: "super_admin"}), do: nil

  defp load_avatar_url(admin) do
    case Ash.load(admin.actor, :avatar_url, actor: admin.actor, tenant: admin.tenant) do
      {:ok, %{avatar_url: url}} -> url
      _ -> nil
    end
  end

  defp profile_form(%{actor: actor, role: "super_admin"} = _admin, params) do
    actor
    |> AshPhoenix.Form.for_update(:update_profile,
      actor: actor,
      as: "profile",
      params: params
    )
    |> to_form()
  end

  defp profile_form(%{actor: actor, tenant: tenant}, params) do
    actor
    |> AshPhoenix.Form.for_update(:update_profile,
      actor: actor,
      tenant: tenant,
      as: "profile",
      params: params
    )
    |> to_form()
  end

  defp password_form(%{actor: actor, role: "super_admin"} = _admin, params) do
    actor
    |> AshPhoenix.Form.for_update(:change_password,
      actor: actor,
      as: "password",
      params: params
    )
    |> to_form()
  end

  defp password_form(%{actor: actor, tenant: tenant}, params) do
    actor
    |> AshPhoenix.Form.for_update(:change_password,
      actor: actor,
      tenant: tenant,
      as: "password",
      params: params
    )
    |> to_form()
  end
end
