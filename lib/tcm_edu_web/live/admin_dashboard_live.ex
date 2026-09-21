defmodule TcmEduWeb.AdminDashboardLive do
  @moduledoc """
  Admin home at `/admin`.

  Super admins see platform-wide tenant stats plus the most recent tenants;
  tenant admins see their own organisation's user/teacher/student counts.
  The two views are intentionally composed differently.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.Organization

  on_mount {TcmEduWeb.AdminAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_admin

    socket =
      case admin.role do
        "super_admin" -> assign_super_stats(socket, admin)
        _ -> assign_tenant_stats(socket, admin)
      end

    {:ok, assign(socket, :page_title, "工作台")}
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, default: "hero-chart-bar"
  attr :tone, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body gap-2.5 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">{@title}</p>
          <span class="flex size-12 items-center justify-center rounded-full bg-base-200">
            <.icon name={@icon} class="size-5" />
          </span>
        </div>
        <p class={["text-3xl font-semibold tabular-nums", @tone]}>{@value}</p>
        <p :if={@hint} class="text-xs text-base-content/60">{@hint}</p>
      </div>
    </div>
    """
  end

  attr :orgs, :list, required: true

  defp tenant_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-pin-rows">
        <thead>
          <tr>
            <th>名称</th>
            <th>Slug</th>
            <th>状态</th>
            <th class="text-right tabular-nums">套餐</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={org <- @orgs} class="hover:bg-base-200">
            <td>
              <div class="flex items-center gap-3">
                <span class="flex size-9 items-center justify-center rounded-box bg-base-200">
                  <.icon name="hero-building-office-2" class="size-4 text-base-content/60" />
                </span>
                <p class="font-medium">{org.name}</p>
              </div>
            </td>
            <td><code class="text-xs">{org.slug}</code></td>
            <td><.status_badge status={org.status} /></td>
            <td class="text-right tabular-nums">
              <span class="badge badge-soft">{plan_label(org.plan)}</span>
            </td>
          </tr>
          <tr :if={@orgs == []}>
            <td colspan="100%">
              <div class="flex flex-col items-center gap-2 py-8">
                <.icon name="hero-building-office-2" class="size-8 text-base-content/40" />
                <p class="text-sm text-base-content/60">还没有租户，先创建一个吧</p>
                <.link navigate="/admin/tenants" class="btn btn-primary btn-sm">去创建</.link>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
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

  defp plan_label(:free), do: "免费版"
  defp plan_label(:pro), do: "专业版"
  defp plan_label(:enterprise), do: "企业版"
  defp plan_label(_), do: "-"

  defp assign_super_stats(socket, admin) do
    orgs =
      case Organization.list_organizations!(actor: admin.actor) do
        orgs when is_list(orgs) -> orgs
      end

    sorted = Enum.sort_by(orgs, & &1.inserted_at, {:desc, DateTime})

    stats = %{
      total: length(orgs),
      active: Enum.count(orgs, &(&1.status == :active)),
      suspended: Enum.count(orgs, &(&1.status == :suspended)),
      archived: Enum.count(orgs, &(&1.status == :archived)),
      plans: orgs |> Enum.group_by(& &1.plan) |> Enum.map(fn {k, v} -> {k, length(v)} end)
    }

    assign(socket, stats: stats, recent_orgs: Enum.take(sorted, 5))
  rescue
    _ -> assign(socket, stats: empty_super_stats(), recent_orgs: [])
  end

  defp assign_tenant_stats(socket, admin) do
    opts = [actor: admin.actor, tenant: admin.tenant]

    users = User |> Ash.Query.for_read(:list_users, %{}, opts) |> Ash.read!()
    students = User |> Ash.Query.for_read(:list_students, %{}, opts) |> Ash.read!()
    teachers = User |> Ash.Query.for_read(:list_teachers, %{}, opts) |> Ash.read!()

    assign(socket,
      stats: %{users: length(users), students: length(students), teachers: length(teachers)}
    )
  rescue
    _ -> assign(socket, stats: %{users: 0, students: 0, teachers: 0})
  end

  defp empty_super_stats, do: %{total: 0, active: 0, suspended: 0, archived: 0, plans: []}
end
