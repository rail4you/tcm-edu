defmodule TcmEduWeb.AdminUsersLive do
  @moduledoc """
  User management at `/admin/users`.

  Super admins pick a tenant schema first; tenant admins are scoped to
  their own tenant. Supports creating users, changing roles,
  enabling/disabling and deleting.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.Organization

  @roles ~w(tenant_admin teacher student)

  on_mount {TcmEduWeb.AdminAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_admin
    tenants = list_tenants(admin)

    tenant =
      if admin.role == "super_admin" do
        default_tenant(tenants)
      else
        admin.tenant
      end

    {:ok,
     socket
     |> assign(:page_title, "用户管理")
     |> assign(:tenants, tenants)
     |> assign(:tenant, tenant)
     |> assign(:modal, nil)
     |> assign(:role_editing, nil)
     |> assign(:deleting, nil)
     |> assign(:create_form, user_form(%{}))
     |> assign(:role_form, role_form(%{}))
     |> load_users()}
  end

  @impl true
  def handle_event("select-tenant", %{"tenant" => tenant}, socket) do
    {:noreply, socket |> assign(:tenant, tenant) |> load_users()}
  end

  def handle_event("open-create", _params, socket) do
    {:noreply, assign(socket, modal: :create, create_form: user_form(%{}))}
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, role_editing: nil, deleting: nil)}
  end

  def handle_event("validate-create", %{"user" => params}, socket) do
    {:noreply, assign(socket, :create_form, user_form(params))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    changeset = create_changeset(params)

    if changeset.valid? do
      attrs = %{
        email: changeset |> get_field(:email) |> String.trim(),
        name: changeset |> get_field(:name) |> empty_to_nil(),
        password: get_field(changeset, :password),
        role: changeset |> get_field(:role) |> to_role()
      }

      case create_user(attrs, actor(socket), socket.assigns.tenant) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(modal: nil)
           |> put_flash(:info, "已创建用户 #{attrs.email}")
           |> load_users()}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, assign(socket, :create_form, Phoenix.Component.to_form(changeset, as: "user"))}
    end
  end

  def handle_event("open-role", %{"id" => id}, socket) do
    case find_user(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "用户不存在")}

      user ->
        {:noreply,
         assign(socket,
           modal: :role,
           role_editing: user,
           role_form: role_form(%{"role" => to_string(user.role)})
         )}
    end
  end

  def handle_event("save-role", %{"user" => %{"role" => role}}, socket) do
    user = socket.assigns.role_editing

    case update_role(user, to_role(role), actor(socket), socket.assigns.tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(modal: nil, role_editing: nil)
         |> put_flash(:info, "角色已更新")
         |> load_users()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("set-status", %{"id" => id, "status" => status}, socket)
      when status in ["active", "disabled"] do
    with user when not is_nil(user) <- find_user(socket, id),
         {:ok, _} <-
           user
           |> Ash.Changeset.for_update(
             :update_status,
             %{status: String.to_existing_atom(status)},
             actor: actor(socket),
             tenant: socket.assigns.tenant
           )
           |> Ash.update() do
      message = if status == "active", do: "已启用", else: "已停用"

      {:noreply, socket |> put_flash(:info, message) |> load_users()}
    else
      nil -> {:noreply, put_flash(socket, :error, "用户不存在")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("confirm-delete", %{"id" => id}, socket) do
    case find_user(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, "用户不存在")}
      user -> {:noreply, assign(socket, modal: :delete, deleting: user)}
    end
  end

  def handle_event("delete", _params, socket) do
    user = socket.assigns.deleting

    case Ash.destroy(user, actor: actor(socket), tenant: socket.assigns.tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(modal: nil, deleting: nil)
         |> put_flash(:info, "已删除 #{user.email}")
         |> load_users()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.admin_shell current_admin={@current_admin} current_page={:users} page_title="用户管理">
        <:page_actions>
          <span :if={@current_admin.role == "super_admin"} class="flex items-center gap-2">
            <.form for={%{}} as={:tenant_filter} phx-change="select-tenant" class="contents">
              <select
                name="tenant"
                class="select select-bordered select-sm w-64"
                aria-label="选择租户"
              >
                <option :for={t <- @tenants} value={t.schema_name} selected={t.schema_name == @tenant}>
                  {t.name}（{t.schema_name}）
                </option>
              </select>
            </.form>
          </span>
          <span :if={@current_admin.role != "super_admin" } class="badge badge-soft badge-info">
            {@tenant}
          </span>
          <button class="btn btn-primary" phx-click="open-create" id="new-user-btn" disabled={is_nil(@tenant)}>
            <.icon name="hero-plus" class="size-4" /> 创建用户
          </button>
        </:page_actions>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-2.5 p-4 sm:p-6">
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>邮箱</th>
                    <th>姓名</th>
                    <th>角色</th>
                    <th>状态</th>
                    <th class="text-right">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={user <- @users} class="hover:bg-base-200" id={"user-#{user.id}"}>
                    <td class="font-medium">{user.email}</td>
                    <td>{user.name || "-"}</td>
                    <td><.role_badge role={user.role} /></td>
                    <td>
                      <span :if={user.status == :active} class="badge badge-soft badge-success">启用</span>
                      <span :if={user.status != :active} class="badge badge-soft badge-error">停用</span>
                    </td>
                    <td>
                      <div class="flex justify-end gap-1">
                        <button class="btn btn-ghost btn-xs" phx-click="open-role" phx-value-id={user.id}>
                          改角色
                        </button>
                        <button
                          :if={user.status == :active}
                          class="btn btn-ghost btn-xs"
                          phx-click="set-status"
                          phx-value-id={user.id}
                          phx-value-status="disabled"
                        >
                          停用
                        </button>
                        <button
                          :if={user.status != :active}
                          class="btn btn-ghost btn-xs"
                          phx-click="set-status"
                          phx-value-id={user.id}
                          phx-value-status="active"
                        >
                          启用
                        </button>
                        <button
                          class="btn btn-ghost btn-xs text-error"
                          phx-click="confirm-delete"
                          phx-value-id={user.id}
                        >
                          删除
                        </button>
                      </div>
                    </td>
                  </tr>
                  <tr :if={@users == []}>
                    <td colspan="100%">
                      <div class="flex flex-col items-center gap-2 py-8">
                        <.icon name="hero-users" class="size-8 text-base-content/40" />
                        <p class="text-sm text-base-content/60">该租户还没有用户</p>
                        <button class="btn btn-sm btn-primary" phx-click="open-create">
                          创建第一个用户
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div :if={@modal == :create} class="modal modal-open" role="dialog" aria-modal="true">
          <div class="modal-box">
            <p class="text-lg font-medium">创建用户</p>
            <p class="py-1 text-xs text-base-content/60">目标租户：<code>{@tenant}</code></p>
            <.form
              for={@create_form}
              id="create-user-form"
              phx-change="validate-create"
              phx-submit="create"
              class="mt-2 flex flex-col gap-2.5"
            >
              <.input field={@create_form[:email]} type="email" label="邮箱" placeholder="user@example.com" required />
              <.input field={@create_form[:name]} type="text" label="姓名" placeholder="可选" />
              <.input field={@create_form[:password]} type="password" label="初始密码" placeholder="至少 6 位" required />
              <.input field={@create_form[:role]} type="select" label="角色" options={role_options()} />
              <div class="modal-action">
                <button type="button" class="btn btn-soft" phx-click="close-modal">取消</button>
                <.button type="submit" phx-disable-with="创建中..." class="btn-primary">创建</.button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="close-modal"></div>
        </div>

        <div :if={@modal == :role} class="modal modal-open" role="dialog" aria-modal="true">
          <div class="modal-box">
            <p class="text-lg font-medium">修改角色：{(@role_editing && @role_editing.email) || ""}</p>
            <.form for={@role_form} id="edit-role-form" phx-submit="save-role" class="mt-2 flex flex-col gap-2.5">
              <.input field={@role_form[:role]} type="select" label="角色" options={role_options()} />
              <div class="modal-action">
                <button type="button" class="btn btn-soft" phx-click="close-modal">取消</button>
                <.button type="submit" phx-disable-with="保存中..." class="btn-primary">保存</.button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="close-modal"></div>
        </div>

        <div :if={@modal == :delete} class="modal modal-open" role="dialog" aria-modal="true">
          <div class="modal-box">
            <p class="text-lg font-medium">删除用户 {(@deleting && @deleting.email) || ""}？</p>
            <p class="py-2 text-sm text-base-content/60">该操作不可恢复，请确认。</p>
            <div class="modal-action">
              <button type="button" class="btn btn-soft" phx-click="close-modal">取消</button>
              <button type="button" class="btn btn-error" phx-click="delete" id="confirm-delete-btn">
                确认删除
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="close-modal"></div>
        </div>
      </.admin_shell>
    </Layouts.app>
    """
  end

  attr :role, :atom, required: true

  defp role_badge(assigns) do
    ~H"""
    <span :if={@role == :tenant_admin} class="badge badge-soft badge-secondary">租户管理员</span>
    <span :if={@role == :teacher} class="badge badge-soft badge-primary">教师</span>
    <span :if={@role == :student} class="badge badge-soft badge-success">学生</span>
    <span :if={@role not in [:tenant_admin, :teacher, :student]} class="badge badge-soft badge-ghost">
      {@role}
    </span>
    """
  end

  defp role_options,
    do: [{"租户管理员", "tenant_admin"}, {"教师", "teacher"}, {"学生", "student"}]

  defp actor(socket), do: socket.assigns.current_admin.actor

  defp list_tenants(%{role: "super_admin", actor: actor}) do
    try do
      Organization.list_organizations!(actor: actor)
      |> Enum.sort_by(& &1.name)
    rescue
      _ -> []
    end
  end

  defp list_tenants(_), do: []

  defp default_tenant(tenants) do
    case Enum.find(tenants, &(&1.schema_name == "tenant_default")) || List.first(tenants) do
      nil -> nil
      org -> org.schema_name
    end
  end

  defp load_users(%{assigns: %{tenant: nil}} = socket), do: assign(socket, :users, [])

  defp load_users(socket) do
    users =
      try do
        User
        |> Ash.Query.for_read(:list_users, %{},
          actor: actor(socket),
          tenant: socket.assigns.tenant
        )
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :users, users)
  end

  defp find_user(socket, id), do: Enum.find(socket.assigns.users, &(&1.id == id))

  defp user_form(params) do
    params |> create_changeset() |> Phoenix.Component.to_form(as: "user")
  end

  defp role_form(params) do
    {%{}, %{role: :string}}
    |> Ecto.Changeset.cast(params, [:role])
    |> Ecto.Changeset.validate_inclusion(:role, @roles)
    |> Phoenix.Component.to_form(as: "user")
  end

  defp create_changeset(params) do
    types = %{email: :string, name: :string, password: :string, role: :string}

    {%{role: "student"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :password, :role])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "邮箱格式不正确")
    |> Ecto.Changeset.validate_length(:password, min: 6, message: "至少 6 位")
    |> Ecto.Changeset.validate_inclusion(:role, @roles)
  end

  defp get_field(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp to_role("tenant_admin"), do: :tenant_admin
  defp to_role("teacher"), do: :teacher
  defp to_role(_), do: :student

  defp create_user(attrs, actor, tenant) do
    case User
         |> Ash.Changeset.for_create(:register_with_role, attrs, actor: actor, tenant: tenant)
         |> Ash.create() do
      {:ok, user} -> {:ok, user}
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  defp update_role(user, role, actor, tenant) do
    case user
         |> Ash.Changeset.for_update(:update_role, %{role: role}, actor: actor, tenant: tenant)
         |> Ash.update() do
      {:ok, user} -> {:ok, user}
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
