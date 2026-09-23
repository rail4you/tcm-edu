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
  alias TcmEduWeb.AdminUserImport

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
     |> assign(:role_filter, "all")
     |> assign(:modal, nil)
     |> assign(:role_editing, nil)
     |> assign(:deleting, nil)
     |> assign(:create_form, user_form(%{}))
     |> assign(:role_form, role_form(%{}))
     |> assign(:import_modal, false)
     |> assign(:import_result, nil)
     |> allow_upload(:import_file,
       accept: ~w(.xlsx),
       max_entries: 1,
       max_file_size: 10_000_000
     )
     |> load_users()}
  end

  @impl true
  def handle_params(%{"tenant" => schema}, _url, socket) when is_binary(schema) do
    # 超管从租户页“管理”链接跳过来时，用 URL 预选租户；租户管理员固定自己的租户。
    socket =
      if socket.assigns.current_admin.role == "super_admin" and
           Enum.any?(socket.assigns.tenants, &(&1.schema_name == schema)) do
        assign(socket, :tenant, schema)
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

  def handle_event("filter-role", %{"role" => role}, socket)
      when role in ["all" | @roles] do
    {:noreply, socket |> assign(:role_filter, role) |> load_users()}
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
    Enum.reduce(rows, {0, errors}, fn {row_number, attrs}, {created, failed} ->
      case User
           |> Ash.Changeset.for_create(:register_with_role, attrs, actor: actor, tenant: tenant)
           |> Ash.create() do
        {:ok, _} ->
          {created + 1, failed}

        {:error, error} ->
          {created, failed ++ [{row_number, "创建失败：#{import_short_message(error)}"}]}
      end
    end)
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
          |> filter_by_role(socket.assigns[:role_filter] || "all")

        query
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :users, users)
  end

  defp filter_by_role(query, "all"), do: query

  defp filter_by_role(query, role) when role in @roles do
    Ash.Query.filter(query, role == ^String.to_existing_atom(role))
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
