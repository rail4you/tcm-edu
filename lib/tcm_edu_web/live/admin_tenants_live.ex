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
      {:noreply, assign(socket, :create_form, Phoenix.Component.to_form(changeset, as: "tenant"))}
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
      {:noreply, assign(socket, :edit_form, Phoenix.Component.to_form(changeset, as: "tenant"))}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.admin_shell current_admin={@current_admin} current_page={:tenants} page_title="租户管理">
        <:page_actions>
          <button class="btn btn-primary" phx-click="open-create" id="new-tenant-btn">
            <.icon name="hero-plus" class="size-4" /> 创建租户
          </button>
        </:page_actions>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-2.5 p-4 sm:p-6">
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>名称</th>
                    <th>Slug</th>
                    <th>Schema</th>
                    <th>状态</th>
                    <th>套餐</th>
                    <th>联系邮箱</th>
                    <th class="text-right">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={org <- @orgs} class="hover:bg-base-200" id={"org-#{org.id}"}>
                    <td class="font-medium">{org.name}</td>
                    <td><code class="text-xs">{org.slug}</code></td>
                    <td><code class="text-xs">{org.schema_name}</code></td>
                    <td><.status_badge status={org.status} /></td>
                    <td>{plan_label(org.plan)}</td>
                    <td>{org.contact_email || "-"}</td>
                    <td>
                      <div class="flex justify-end gap-1">
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="open-edit"
                          phx-value-id={org.id}
                        >
                          编辑
                        </button>
                        <button
                          :if={org.status == :active}
                          class="btn btn-ghost btn-xs"
                          phx-click="transition"
                          phx-value-id={org.id}
                          phx-value-to="suspend"
                        >
                          暂停
                        </button>
                        <button
                          :if={org.status != :active}
                          class="btn btn-ghost btn-xs"
                          phx-click="transition"
                          phx-value-id={org.id}
                          phx-value-to="activate"
                        >
                          恢复
                        </button>
                        <button
                          :if={org.status != :archived}
                          class="btn btn-ghost btn-xs"
                          phx-click="transition"
                          phx-value-id={org.id}
                          phx-value-to="archive"
                        >
                          归档
                        </button>
                        <button
                          class="btn btn-ghost btn-xs text-error"
                          phx-click="confirm-delete"
                          phx-value-id={org.id}
                        >
                          删除
                        </button>
                      </div>
                    </td>
                  </tr>
                  <tr :if={@orgs == []}>
                    <td colspan="100%">
                      <div class="flex flex-col items-center gap-2 py-8">
                        <.icon name="hero-building-office-2" class="size-8 text-base-content/40" />
                        <p class="text-sm text-base-content/60">还没有租户</p>
                        <button class="btn btn-sm btn-primary" phx-click="open-create">
                          创建第一个租户
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
            <p class="text-lg font-medium">创建租户</p>
            <p class="py-1 text-xs text-base-content/60">创建后将自动建 schema 并初始化数据</p>
            <.form
              for={@create_form}
              id="create-tenant-form"
              phx-change="validate-create"
              phx-submit="create"
              class="mt-2 flex flex-col gap-2.5"
            >
              <.input field={@create_form[:name]} type="text" label="机构名称" placeholder="例：广州中医药大学" required />
              <.input
                field={@create_form[:slug]}
                type="text"
                label="Slug（作为 schema 后缀，不可更改）"
                placeholder="例：gzu-tcm"
                required
              />
              <.input
                field={@create_form[:contact_email]}
                type="email"
                label="联系邮箱"
                placeholder="admin@example.com"
              />
              <.input
                field={@create_form[:plan]}
                type="select"
                label="套餐"
                options={plan_options()}
              />
              <div class="modal-action">
                <button type="button" class="btn btn-soft" phx-click="close-modal">取消</button>
                <.button type="submit" phx-disable-with="创建中..." class="btn-primary">创建</.button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="close-modal"></div>
        </div>

        <div :if={@modal == :edit} class="modal modal-open" role="dialog" aria-modal="true">
          <div class="modal-box">
            <p class="text-lg font-medium">编辑租户：{(@editing && @editing.name) || ""}</p>
            <.form
              for={@edit_form}
              id="edit-tenant-form"
              phx-change="validate-edit"
              phx-submit="edit"
              class="mt-2 flex flex-col gap-2.5"
            >
              <.input field={@edit_form[:name]} type="text" label="机构名称" required />
              <.input field={@edit_form[:contact_email]} type="email" label="联系邮箱" />
              <.input field={@edit_form[:contact_phone]} type="text" label="联系电话" />
              <.input field={@edit_form[:description]} type="textarea" label="简介" rows="3" />
              <.input field={@edit_form[:plan]} type="select" label="套餐" options={plan_options()} />
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
            <p class="text-lg font-medium">删除租户 {(@deleting && @deleting.name) || ""}？</p>
            <div class="alert alert-soft alert-error mt-2">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              <p class="text-sm">将级联删除该租户 schema 下所有数据，不可恢复。</p>
            </div>
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

    assign(socket, :orgs, orgs)
  end

  defp find_org(socket, id), do: Enum.find(socket.assigns.orgs, &(&1.id == id))

  defp tenant_form(params, kind \\ :create) do
    params
    |> changeset_for(kind)
    |> Phoenix.Component.to_form(as: "tenant")
  end

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
