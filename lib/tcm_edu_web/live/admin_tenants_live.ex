defmodule TcmEduWeb.AdminTenantsLive do
  @moduledoc """
  Tenant management at `/admin/tenants` (super admins only).

  Mirrors the old React admin tenants page: create tenants (which
  provisions a dedicated schema), edit details, suspend/activate/archive,
  and hard-delete with confirmation.

  表单走 `AshPhoenix.Form`:
    * 创建:`for_create(Organization, :create_with_schema, ...)`
      (字段 / 约束直接来自资源,无需手写 changeset)
    * 编辑:`for_update(org, :update_details, ...)`
      (form 的 source 字段就是 org,改完自动 diff 应用到资源)
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  alias TcmEdu.System.Organization

  on_mount {TcmEduWeb.AdminAuth, :ensure_super_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "租户管理")
     |> assign(:modal, nil)
     |> assign(:editing, nil)
     |> assign(:deleting, nil)
     |> assign(:admin_counts, %{})
     |> assign(:create_form, create_form(socket))
     |> assign(:edit_form, nil)
     |> load_orgs()}
  end

  @impl true
  def handle_event("open-create", _params, socket) do
    {:noreply, assign(socket, modal: :create, create_form: create_form(socket))}
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, editing: nil, deleting: nil)}
  end

  def handle_event("validate-create", %{"tenant" => params}, socket) do
    {:noreply,
     assign(socket, :create_form, AshPhoenix.Form.validate(socket.assigns.create_form, params))}
  end

  def handle_event("create", %{"tenant" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.create_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, org} ->
        {:noreply,
         socket
         |> assign(modal: nil)
         |> put_flash(:info, "租户已创建，schema：#{org.schema_name}")
         |> load_orgs()}

      {:error, form} ->
        {:noreply, assign(socket, :create_form, form)}
    end
  end

  def handle_event("open-edit", %{"id" => id}, socket) do
    case find_org(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "租户不存在")}

      org ->
        {:noreply, assign(socket, modal: :edit, editing: org, edit_form: edit_form(socket, org))}
    end
  end

  def handle_event("validate-edit", %{"tenant" => params}, socket) do
    {:noreply,
     assign(socket, :edit_form, AshPhoenix.Form.validate(socket.assigns.edit_form, params))}
  end

  def handle_event("edit", %{"tenant" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(modal: nil, editing: nil)
         |> put_flash(:info, "已保存")
         |> load_orgs()}

      {:error, form} ->
        {:noreply, assign(socket, :edit_form, form)}
    end
  end

  def handle_event("transition", %{"id" => id, "to" => to}, socket)
      when to in ["suspend", "activate", "archive"] do
    action = String.to_existing_atom(to)

    with org when not is_nil(org) <- find_org(socket, id),
         {:ok, _} <-
           org
           |> Ash.Changeset.for_update(action, %{}, actor: actor(socket))
           |> Ash.update() do
      {:noreply, socket |> put_flash(:info, "#{org.name}：#{transition_label(to)}") |> load_orgs()}
    else
      nil -> {:noreply, put_flash(socket, :error, "租户不存在")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("confirm-delete", %{"id" => id}, socket) do
    case find_org(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, "租户不存在")}
      org -> {:noreply, assign(socket, modal: :delete, deleting: org)}
    end
  end

  def handle_event("delete", _params, socket) do
    org = socket.assigns.deleting

    case Ash.destroy(org, actor: actor(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(modal: nil, deleting: nil)
         |> put_flash(:info, "已删除租户 #{org.name}（schema 已级联删除）")
         |> load_orgs()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={@status == :active} class="badge badge-soft badge-success">运营中</span>
    <span :if={@status == :suspended} class="badge badge-soft badge-error">已暂停</span>
    <span :if={@status not in [:active, :suspended]} class="badge badge-soft badge-ghost">已归档</span>
    """
  end

  defp plan_options,
    do: [{"免费版", "free"}, {"专业版", "pro"}, {"企业版", "enterprise"}]

  defp plan_label(:free), do: "免费版"
  defp plan_label(:pro), do: "专业版"
  defp plan_label(:enterprise), do: "企业版"
  defp plan_label(_), do: "-"

  defp transition_label("suspend"), do: "已暂停"
  defp transition_label("activate"), do: "已恢复"
  defp transition_label("archive"), do: "已归档"

  defp actor(socket), do: socket.assigns.current_admin.actor

  defp load_orgs(socket) do
    orgs =
      try do
        Organization.list_organizations!(actor: actor(socket))
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    socket
    |> assign(:orgs, orgs)
    |> assign(:admin_counts, admin_counts(orgs, actor(socket)))
  end

  defp admin_counts(orgs, actor) do
    Map.new(orgs, fn org ->
      count =
        try do
          org.schema_name
          # 由于 AdminAuth 的 import 限制,这里直接走底层 read,绕过策略
          # (User 是 multitenancy :context,需要 tenant:)
          # 简化起见使用 list_admins read action
          TcmEdu.Accounts.User
          |> Ash.Query.for_read(:list_admins, %{},
            actor: actor,
            tenant: org.schema_name,
            authorize?: false
          )
          |> Ash.read!()
          |> length()
        rescue
          _ -> 0
        end

      {org.id, count}
    end)
  end

  defp find_org(socket, id), do: Enum.find(socket.assigns.orgs, &(&1.id == id))

  # 创建表单:`:create_with_schema` action 的 accept 列表决定字段
  # (name/slug/contact_email/contact_phone/description/logo_url/plan/expires_at),
  # `slug` 的 `match: ~r/^[a-z0-9].../` 约束和 `plan` 的 `one_of` 自动生效。
  defp create_form(socket) do
    Organization
    |> AshPhoenix.Form.for_create(:create_with_schema,
      actor: actor(socket),
      as: "tenant"
    )
    |> to_form(as: "tenant")
  end

  # 编辑表单:`AshPhoenix.Form.for_update/3` 把 record 注入到 source,
  # 字段初始值即 `org.<attr>`,无需手写 `course_to_params/1` 类的转换。
  defp edit_form(socket, org) do
    AshPhoenix.Form.for_update(org, :update_details,
      actor: actor(socket),
      as: "tenant"
    )
    |> to_form(as: "tenant")
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
