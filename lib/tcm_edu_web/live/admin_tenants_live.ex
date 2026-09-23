defmodule TcmEduWeb.AdminTenantsLive do
  @moduledoc """
  Tenant management at `/admin/tenants` (super admins only).

  Mirrors the old React admin tenants page: create tenants (which
  provisions a dedicated schema), edit details, suspend/activate/archive,
  and hard-delete with confirmation.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  alias TcmEdu.System.Organization
  alias TcmEdu.Accounts.User

  on_mount {TcmEduWeb.AdminAuth, :ensure_super_admin}

  @plans ~w(free pro enterprise)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "租户管理")
     |> assign(:modal, nil)
     |> assign(:editing, nil)
     |> assign(:deleting, nil)
     |> assign(:admin_counts, %{})
     |> assign(:create_form, tenant_form(%{}))
     |> assign(:edit_form, tenant_form(%{}))
     |> load_orgs()}
  end

  @impl true
  def handle_event("open-create", _params, socket) do
    {:noreply, assign(socket, modal: :create, create_form: tenant_form(%{}))}
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, editing: nil, deleting: nil)}
  end

  def handle_event("validate-create", %{"tenant" => params}, socket) do
    {:noreply, assign(socket, :create_form, tenant_form(params))}
  end

  def handle_event("create", %{"tenant" => params}, socket) do
    changeset = create_changeset(params)

    if changeset.valid? do
      attrs = %{
        name: get_field(changeset, :name),
        slug: get_field(changeset, :slug) |> String.downcase(),
        contact_email: empty_to_nil(get_field(changeset, :contact_email)),
        plan: String.to_existing_atom(get_field(changeset, :plan) || "free")
      }

      case create_organization(attrs, actor(socket)) do
        {:ok, org} ->
          {:noreply,
           socket
           |> assign(modal: nil)
           |> put_flash(:info, "租户已创建，schema：#{org.schema_name}")
           |> load_orgs()}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, assign(socket, :create_form, tenant_form(params))}
    end
  end

  def handle_event("open-edit", %{"id" => id}, socket) do
    case find_org(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "租户不存在")}

      org ->
        params = %{
          "name" => org.name,
          "contact_email" => org.contact_email || "",
          "contact_phone" => org.contact_phone || "",
          "description" => org.description || "",
          "plan" => to_string(org.plan || :free)
        }

        {:noreply, assign(socket, modal: :edit, editing: org, edit_form: tenant_form(params))}
    end
  end

  def handle_event("validate-edit", %{"tenant" => params}, socket) do
    {:noreply, assign(socket, :edit_form, tenant_form(params, :edit))}
  end

  def handle_event("edit", %{"tenant" => params}, socket) do
    changeset = edit_changeset(params)

    if changeset.valid? do
      attrs = %{
        name: get_field(changeset, :name),
        contact_email: empty_to_nil(get_field(changeset, :contact_email)),
        contact_phone: empty_to_nil(get_field(changeset, :contact_phone)),
        description: empty_to_nil(get_field(changeset, :description)),
        plan: String.to_existing_atom(get_field(changeset, :plan) || "free")
      }

      case update_organization(socket.assigns.editing, attrs, actor(socket)) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(modal: nil, editing: nil)
           |> put_flash(:info, "已保存")
           |> load_orgs()}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, assign(socket, :edit_form, tenant_form(params, :edit))}
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

  # 每个租户的 tenant_admin 人数（超管一眼看到哪些租户还没配管理员）。
  defp admin_counts(orgs, actor) do
    Map.new(orgs, fn org ->
      count =
        try do
          User
          |> Ash.Query.for_read(:list_admins, %{}, actor: actor, tenant: org.schema_name)
          |> Ash.read!()
          |> length()
        rescue
          _ -> 0
        end

      {org.id, count}
    end)
  end

  defp find_org(socket, id), do: Enum.find(socket.assigns.orgs, &(&1.id == id))

  defp tenant_form(params, kind \\ :create) do
    params
    |> changeset_for(kind)
    |> put_validate_action(params)
    |> Phoenix.Component.to_form(as: "tenant")
  end

  # 刚打开弹窗时 params 为空，不挂 action，避免“必填”错误提前冒出来；
  # 用户交互后（validate/submit）再挂 :validate，否则 to_form 会丢弃全部错误、
  # 非法提交时弹窗“毫无反应”（slug 如 "gz" 过短被打回却无任何提示）。
  defp put_validate_action(changeset, params) when params == %{}, do: changeset
  defp put_validate_action(changeset, _params), do: Map.put(changeset, :action, :validate)

  defp create_changeset(params), do: changeset_for(params, :create)
  defp edit_changeset(params), do: changeset_for(params, :edit)

  defp changeset_for(params, kind) do
    types = %{
      name: :string,
      slug: :string,
      contact_email: :string,
      contact_phone: :string,
      description: :string,
      plan: :string
    }

    {%{plan: "free"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:name, :plan])
    |> Ecto.Changeset.update_change(:contact_email, &empty_to_nil/1)
    |> then(fn cs ->
      if kind == :create,
        do:
          cs
          |> Ecto.Changeset.validate_required([:slug])
          |> Ecto.Changeset.validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/,
            message: "小写字母/数字/连字符，3~32 位"
          ),
        else: cs
    end)
    |> Ecto.Changeset.validate_format(:contact_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "邮箱格式不正确"
    )
    |> Ecto.Changeset.validate_inclusion(:plan, @plans)
  end

  defp get_field(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp create_organization(attrs, actor) do
    case Organization.create_organization(attrs, actor: actor) do
      {:ok, org} -> {:ok, org}
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  defp update_organization(org, attrs, actor) do
    case org |> Ash.Changeset.for_update(:update_details, attrs, actor: actor) |> Ash.update() do
      {:ok, org} -> {:ok, org}
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
