defmodule TcmEduWeb.AdminUsersLive do
  @moduledoc """
  User management at `/admin/users`.

  Super admins pick a tenant schema first; tenant admins are scoped to
  their own tenant. Supports creating users, changing roles,
  enabling/disabling, resetting password (super admin only) and deleting.

  表单走 `AshPhoenix.Form`:
    * 创建:`for_create(User, :register_with_role, ...)`,`password` 是 argument
      (`AshPhoenix.Form` 同时把 attribute + argument 当作字段渲染);
    * 改角色:`for_update(user, :update_role, ...)`,`role` 是 argument;
    * 重置密码:`for_update(user, :reset_password, ...)`,`password` /
      `password_confirmation` 都是 argument。
  启停 / 删除 / xlsx 导入不在表单范围,保持 `Ash.Changeset` 直接调用。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Classes.ClassGroup
  alias TcmEdu.System.Organization
  alias TcmEduWeb.AdminUserImport
  alias TcmEduWeb.UserAvatar

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
     |> assign(:role_filter, "all")
     |> assign(:class_filter, "all")
     |> assign(:class_groups, load_class_groups(actor(socket), tenant))
     |> assign(:modal, nil)
     |> assign(:role_editing, nil)
     |> assign(:deleting, nil)
     |> assign(:password_editing, nil)
     |> assign(:editing, nil)
     |> assign(:edit_form, nil)
     |> assign(:create_form, create_form(actor(socket), tenant, %{}))
     |> assign(:role_form, nil)
     |> assign(:password_form, nil)
     |> assign(:import_modal, false)
     |> assign(:import_result, nil)
     |> allow_upload(:import_file,
       accept: ~w(.xlsx),
       max_entries: 1,
       max_file_size: 10_000_000
     )
     |> UserAvatar.allow_avatar_upload()
     |> load_users()}
  end

  @impl true
  def handle_params(%{"tenant" => schema}, _url, socket) when is_binary(schema) do
    socket =
      if socket.assigns.current_admin.role == "super_admin" and
           Enum.any?(socket.assigns.tenants, &(&1.schema_name == schema)) do
        socket
        |> assign(:tenant, schema)
        |> assign(:class_filter, "all")
        |> assign(:class_groups, load_class_groups(actor(socket), schema))
      else
        socket
      end

    {:noreply, load_users(socket)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select-tenant", %{"tenant" => tenant}, socket) do
    {:noreply, push_patch(socket, to: "/admin/users?tenant=#{tenant}")}
  end

  def handle_event("filter-role", %{"role" => role}, socket) do
    # role 是合法值已由上层校验,这里只 reload
    {:noreply, socket |> assign(:role_filter, role) |> load_users()}
  end

  def handle_event("filter-class", %{"class" => class_id}, socket) do
    {:noreply, socket |> assign(:class_filter, class_id) |> load_users()}
  end

  def handle_event("open-edit", %{"id" => id}, socket) do
    case find_user(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "用户不存在")}

      user ->
        {:noreply,
         socket
         |> assign(
           modal: :edit,
           editing: user,
           edit_form: edit_form(actor(socket), socket.assigns.tenant, user, %{})
         )
         |> UserAvatar.reset_avatar_upload()}
    end
  end

  def handle_event("validate-edit", %{"user" => params}, socket) do
    {:noreply,
     assign(socket, :edit_form, AshPhoenix.Form.validate(socket.assigns.edit_form, params))}
  end

  def handle_event("save-edit", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, user} ->
        case UserAvatar.consume_avatar(socket, user, socket.assigns.current_admin) do
          {:error, message} ->
            {:noreply, socket |> assign(:edit_form, form) |> put_flash(:error, message)}

          _ok ->
            {:noreply,
             socket
             |> assign(modal: nil, editing: nil, edit_form: nil)
             |> put_flash(:info, "已更新 #{user.name || user.email} 的资料")
             |> load_users()}
        end

      {:error, form} ->
        {:noreply, assign(socket, :edit_form, form)}
    end
  end

  def handle_event("remove-avatar", _params, socket) do
    user = socket.assigns.editing

    case UserAvatar.remove_avatar(user, socket.assigns.current_admin) do
      :ok ->
        socket = load_users(socket)
        fresh = find_user(socket, user.id)

        {:noreply,
         socket
         |> assign(
           editing: fresh,
           edit_form: edit_form(actor(socket), socket.assigns.tenant, fresh, %{})
         )
         |> put_flash(:info, "头像已移除")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("open-create", _params, socket) do
    {:noreply,
     assign(socket,
       modal: :create,
       create_form: create_form(actor(socket), socket.assigns.tenant, %{})
     )}
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply,
     assign(socket,
       modal: nil,
       role_editing: nil,
       deleting: nil,
       password_editing: nil,
       editing: nil,
       edit_form: nil
     )}
  end

  def handle_event("validate-create", %{"user" => params}, socket) do
    {:noreply,
     assign(socket, :create_form, AshPhoenix.Form.validate(socket.assigns.create_form, params))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.create_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(modal: nil)
         |> put_flash(:info, "已创建用户 #{user.email}")
         |> load_users()}

      {:error, form} ->
        {:noreply, assign(socket, :create_form, form)}
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
           role_form:
             role_form(actor(socket), socket.assigns.tenant, user, %{
               "role" => to_string(user.role)
             })
         )}
    end
  end

  def handle_event("save-role", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.role_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(modal: nil, role_editing: nil, role_form: nil)
         |> put_flash(:info, "角色已更新")
         |> load_users()}

      {:error, form} ->
        {:noreply, assign(socket, :role_form, form)}
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

  def handle_event("open-password", %{"id" => id}, socket) do
    if socket.assigns.current_admin.role != "super_admin" do
      {:noreply, put_flash(socket, :error, "仅超级管理员可重置密码")}
    else
      case find_user(socket, id) do
        nil ->
          {:noreply, put_flash(socket, :error, "用户不存在")}

        user ->
          {:noreply,
           assign(socket,
             modal: :password,
             password_editing: user,
             password_form: password_form(actor(socket), socket.assigns.tenant, user, %{})
           )}
      end
    end
  end

  def handle_event("validate-password", %{"user" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :password_form,
       AshPhoenix.Form.validate(socket.assigns.password_form, params)
     )}
  end

  def handle_event("save-password", %{"user" => params}, socket) do
    user = socket.assigns.password_editing
    form = AshPhoenix.Form.validate(socket.assigns.password_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(modal: nil, password_editing: nil, password_form: nil)
         |> put_flash(:info, "已重置 #{user.email} 的密码")
         |> load_users()}

      {:error, form} ->
        {:noreply, assign(socket, :password_form, form)}
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

  def handle_event("open-import", _params, socket) do
    if socket.assigns.tenant do
      {:noreply, assign(socket, import_modal: true, import_result: nil)}
    else
      {:noreply, put_flash(socket, :error, "请先选择目标租户")}
    end
  end

  def handle_event("close-import", _params, socket) do
    {:noreply,
     socket
     |> assign(import_modal: false, import_result: nil)
     |> load_users()}
  end

  def handle_event("validate-import", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :import_file, ref)}
  end

  def handle_event("import", _params, socket) do
    consumed =
      consume_uploaded_entries(socket, :import_file, fn %{path: path}, entry ->
        cond do
          not String.ends_with?(String.downcase(entry.client_name), ".xlsx") ->
            {:ok, {:file_error, "只支持 .xlsx 文件"}}

          true ->
            case AdminUserImport.import_file(path) do
              {:ok, rows, errors} -> {:ok, {:rows, rows, errors}}
              {:error, message} -> {:ok, {:file_error, message}}
            end
        end
      end)

    case consumed do
      [] ->
        {:noreply, put_flash(socket, :error, "请先选择要导入的 xlsx 文件")}

      [{:file_error, message}] ->
        {:noreply, assign(socket, :import_result, %{created: 0, failed: [{"—", message}]})}

      [{:rows, rows, errors}] ->
        tenant = socket.assigns.tenant
        {created, failed} = create_imported_users(rows, errors, actor(socket), tenant)

        {:noreply,
         socket
         |> assign(:import_result, %{created: created, failed: failed})
         |> load_users()}
    end
  end

  attr :role, :atom, required: true

  defp user_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp user_initial(%{email: email}) when is_binary(email) and byte_size(email) > 0 do
    email |> String.trim() |> String.first() |> String.upcase()
  end

  defp user_initial(_), do: "U"

  defp create_imported_users(rows, errors, actor, tenant) do
    {created, failed, _cache} =
      Enum.reduce(rows, {0, errors, %{}}, fn {row_number, attrs}, {created, failed, cache} ->
        {class_group_id, cache} = resolve_class(attrs[:class_name], cache, actor, tenant)

        attrs =
          attrs
          |> Map.drop([:class_name])
          |> put_class_group_id(class_group_id)

        case User
             |> Ash.Changeset.for_create(:register_with_role, attrs, actor: actor, tenant: tenant)
             |> Ash.create() do
          {:ok, _} ->
            {created + 1, failed, cache}

          {:error, error} ->
            {created, failed ++ [{row_number, "创建失败：#{import_short_message(error)}"}], cache}
        end
      end)

    {created, failed}
  end

  defp put_class_group_id(attrs, nil), do: attrs
  defp put_class_group_id(attrs, id), do: Map.put(attrs, :class_group_id, id)

  defp resolve_class(name, cache, _actor, _tenant) when name in [nil, ""], do: {nil, cache}

  defp resolve_class(name, cache, actor, tenant) do
    name = String.trim(name)

    case Map.fetch(cache, name) do
      {:ok, id} ->
        {id, cache}

      :error ->
        id = find_or_create_class(name, actor, tenant)
        {id, Map.put(cache, name, id)}
    end
  end

  # 导入时按名称自动创建班级（已存在则复用）。
  defp find_or_create_class(name, actor, tenant) do
    case read_class_by_name(name, actor, tenant) do
      {:ok, %ClassGroup{id: id}} ->
        id

      _ ->
        case ClassGroup
             |> Ash.Changeset.for_create(:create, %{name: name}, actor: actor, tenant: tenant)
             |> Ash.create() do
          {:ok, %ClassGroup{id: id}} -> id
          _ -> read_class_by_name(name, actor, tenant) |> elem(1) |> Map.get(:id)
        end
    end
  end

  defp read_class_by_name(name, actor, tenant) do
    ClassGroup
    |> Ash.Query.filter(name == ^name)
    |> Ash.read_one(actor: actor, tenant: tenant)
  end

  defp import_short_message(error) do
    error |> Exception.message() |> String.split("\n") |> hd() |> String.trim()
  rescue
    _ -> "未知错误"
  end

  defp upload_error_to_string(:too_large), do: "文件太大（最大 10MB）"
  defp upload_error_to_string(:too_many_files), do: "一次只能上传 1 个文件"
  defp upload_error_to_string(:not_accepted), do: "只支持 .xlsx 文件"
  defp upload_error_to_string(_), do: "文件上传失败"

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

  defp role_options("super_admin"),
    do: [{"租户管理员", "tenant_admin"}, {"教师", "teacher"}, {"学生", "student"}]

  # 租户管理员只能创建教师/学生（能否分配 tenant_admin 由后端守卫
  # RestrictTenantAdminRole 最终把关）。
  defp role_options(_), do: [{"教师", "teacher"}, {"学生", "student"}]

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
        query =
          User
          |> Ash.Query.for_read(:list_users, %{},
            actor: actor(socket),
            tenant: socket.assigns.tenant
          )
          |> Ash.Query.load([:class_group, :avatar_url])
          |> filter_by_role(socket.assigns[:role_filter] || "all")

        query
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> filter_by_class(socket.assigns[:class_filter] || "all")
      rescue
        _ -> []
      end

    assign(socket, :users, users)
  end

  defp filter_by_class(users, "all"), do: users
  defp filter_by_class(users, class_id), do: Enum.filter(users, &(&1.class_group_id == class_id))

  defp filter_by_role(query, "all"), do: query

  defp filter_by_role(query, role) do
    Ash.Query.filter(query, role == ^String.to_existing_atom(role))
  end

  defp find_user(socket, id), do: Enum.find(socket.assigns.users, &(&1.id == id))

  defp load_class_groups(actor, tenant) when is_binary(tenant) do
    try do
      ClassGroup
      |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!()
    rescue
      _ -> []
    end
  end

  defp load_class_groups(_actor, _tenant), do: []

  # `:register_with_role` action 同时接受 attribute (`email`/`name`/`role`...) +
  # argument (`password`)。`AshPhoenix.Form` 会把两者都当作字段渲染,
  # `password` 字段名对应 argument 名。`email` 格式校验由资源 attribute
  # 约束 + 自定义 validate 块统一提供(此处保留旧的中文错误消息)。
  defp create_form(actor, tenant, params) do
    User
    |> AshPhoenix.Form.for_create(:register_with_role,
      actor: actor,
      tenant: tenant,
      as: "user",
      params: params
    )
    |> to_form()
  end

  # `:update_role` action 只接受 `role` argument。
  defp role_form(actor, tenant, user, params) do
    AshPhoenix.Form.for_update(user, :update_role,
      actor: actor,
      tenant: tenant,
      as: "user",
      params: params
    )
    |> to_form()
  end

  # `:reset_password` action 只接受 `password` / `password_confirmation` arguments,
  # `confirm(:password, :password_confirmation)` 校验写在 action 上。
  defp password_form(actor, tenant, user, params) do
    AshPhoenix.Form.for_update(user, :reset_password,
      actor: actor,
      tenant: tenant,
      as: "user",
      params: params
    )
    |> to_form()
  end

  # `:admin_update_user` 接受资料字段 + `class_group_id`。
  defp edit_form(actor, tenant, user, params) do
    AshPhoenix.Form.for_update(user, :admin_update_user,
      actor: actor,
      tenant: tenant,
      as: "user",
      params: params
    )
    |> to_form()
  end

  defp class_options(class_groups) do
    [{"未分班", ""} | Enum.map(class_groups, &{&1.name, &1.id})]
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
