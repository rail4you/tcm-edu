defmodule TcmEduWeb.AdminClassesLive do
  @moduledoc """
  班级管理独立页面 `/admin/classes`。

  班级（`TcmEdu.Classes.ClassGroup`）用于组织学生：新建 / 重命名 / 删除，
  并展示每个班级的学生人数。删除班级后，原班级学生自动置为「未分班」
  （FK `on_delete: :nilify`）。

  超级管理员可切换租户（`?tenant=`）；租户管理员固定为本租户。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Classes.ClassGroup
  alias TcmEdu.System.Organization

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
     |> assign(:page_title, "班级管理")
     |> assign(:tenants, tenants)
     |> assign(:tenant, tenant)
     |> assign(:class_form, class_form(actor(socket), tenant, %{}))
     |> reload()}
  end

  @impl true
  def handle_params(%{"tenant" => schema}, _url, socket) when is_binary(schema) do
    socket =
      if socket.assigns.current_admin.role == "super_admin" and
           Enum.any?(socket.assigns.tenants, &(&1.schema_name == schema)) do
        socket
        |> assign(:tenant, schema)
        |> assign(:class_form, class_form(actor(socket), schema, %{}))
      else
        socket
      end

    {:noreply, reload(socket)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, reload(socket)}

  @impl true
  def handle_event("select-tenant", %{"tenant" => tenant}, socket) do
    {:noreply, push_patch(socket, to: "/admin/classes?tenant=#{tenant}")}
  end

  def handle_event("validate-class", %{"class_group" => params}, socket) do
    {:noreply,
     assign(socket, :class_form, AshPhoenix.Form.validate(socket.assigns.class_form, params))}
  end

  def handle_event("create-class", %{"class_group" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.class_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:class_form, class_form(actor(socket), socket.assigns.tenant, %{}))
         |> put_flash(:info, "班级已创建")
         |> reload()}

      {:error, form} ->
        {:noreply, assign(socket, :class_form, form)}
    end
  end

  def handle_event("rename-class", %{"class_id" => id, "name" => name}, socket) do
    with %ClassGroup{} = class_group <- find_class_group(socket, id),
         {:ok, _} <-
           class_group
           |> Ash.Changeset.for_update(:update, %{name: name},
             actor: actor(socket),
             tenant: socket.assigns.tenant
           )
           |> Ash.update() do
      {:noreply, socket |> put_flash(:info, "班级已重命名") |> reload()}
    else
      nil -> {:noreply, put_flash(socket, :error, "班级不存在")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("delete-class", %{"id" => id}, socket) do
    case find_class_group(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "班级不存在")}

      %ClassGroup{} = class_group ->
        case Ash.destroy(class_group, actor: actor(socket), tenant: socket.assigns.tenant) do
          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}

          _ok ->
            {:noreply,
             socket
             |> put_flash(:info, "班级已删除，原班级学生已置为未分班")
             |> reload()}
        end
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp reload(%{assigns: %{tenant: nil}} = socket) do
    socket |> assign(:class_groups, []) |> assign(:student_counts, %{})
  end

  defp reload(socket) do
    socket
    |> assign(:class_groups, load_class_groups(actor(socket), socket.assigns.tenant))
    |> assign(:student_counts, load_student_counts(actor(socket), socket.assigns.tenant))
  end

  defp load_class_groups(actor, tenant) do
    try do
      ClassGroup
      |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!()
    rescue
      _ -> []
    end
  end

  defp load_student_counts(actor, tenant) do
    try do
      User
      |> Ash.Query.for_read(:list_users, %{}, actor: actor, tenant: tenant)
      |> Ash.read!()
      |> Enum.reject(&is_nil(&1.class_group_id))
      |> Enum.frequencies_by(& &1.class_group_id)
    rescue
      _ -> %{}
    end
  end

  defp find_class_group(socket, id) do
    Enum.find(socket.assigns.class_groups, &(&1.id == id))
  end

  defp class_form(actor, tenant, params) do
    ClassGroup
    |> AshPhoenix.Form.for_create(:create,
      actor: actor,
      tenant: tenant,
      as: "class_group",
      params: params
    )
    |> to_form()
  end

  defp actor(socket), do: socket.assigns.current_admin.actor

  defp list_tenants(%{role: "super_admin", actor: actor}) do
    try do
      Organization.list_organizations!(actor: actor) |> Enum.sort_by(& &1.name)
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

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
