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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.admin_shell current_admin={@current_admin} current_page={:dashboard} page_title="工作台">
        <div :if={@current_admin.role == "super_admin"} class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
          <.stat_card title="租户总数" value={@stats.total} hint="平台累计创建" icon="hero-building-office-2" />
          <.stat_card
            title="运营中"
            value={@stats.active}
            hint="状态为 active 的租户"
            icon="hero-check-circle"
            tone="text-success"
          />
          <.stat_card
            title="已暂停"
            value={@stats.suspended}
            hint="需要跟进处理"
            icon="hero-pause-circle"
            tone="text-warning"
          />
          <.stat_card title="已归档" value={@stats.archived} hint="历史保留数据" icon="hero-archive-box" />
        </div>

        <div :if={@current_admin.role == "super_admin"} class="grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div class="card bg-base-100 shadow-sm xl:col-span-2">
            <div class="card-body gap-2.5 p-4 sm:p-6">
              <div class="flex items-center justify-between gap-2">
                <p class="font-medium">最近创建的租户</p>
                <.link navigate="/admin/tenants" class="link link-primary text-xs">查看全部</.link>
              </div>
              <.tenant_table orgs={@recent_orgs} />
            </div>
          </div>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body gap-2.5 p-4 sm:p-6">
              <p class="font-medium">快捷入口</p>
              <div class="flex flex-col gap-2">
                <.link navigate="/admin/tenants" class="btn btn-soft btn-primary justify-start">
                  <.icon name="hero-plus" class="size-4" /> 创建租户
                </.link>
                <.link navigate="/admin/users" class="btn btn-soft justify-start">
                  <.icon name="hero-users" class="size-4" /> 用户管理
                </.link>
              </div>
              <div class="divider my-1" />
              <p class="text-xs text-base-content/60">套餐分布</p>
              <div class="flex flex-wrap gap-2">
                <span :for={{plan, count} <- @stats.plans} class="badge badge-soft">
                  {plan_label(plan)} · {count}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div :if={@current_admin.role == "tenant_admin"} class="flex flex-col gap-6">
          <div class="alert alert-soft alert-info">
            <.icon name="hero-information-circle" class="size-5" />
            <p class="text-sm">
              当前机构：<span class="font-medium">{@current_admin.tenant}</span>
            </p>
          </div>
          <div class="grid grid-cols-1 gap-6 md:grid-cols-3">
            <.stat_card title="用户总数" value={@stats.users} hint="本机构全部用户" icon="hero-users" />
            <.stat_card title="教师" value={@stats.teachers} hint="在职授课教师" icon="hero-academic-cap" />
            <.stat_card title="学生" value={@stats.students} hint="在册学习学生" icon="hero-book-open" />
          </div>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body gap-2.5 p-4 sm:p-6">
              <div class="flex items-center justify-between gap-2">
                <p class="font-medium">快捷入口</p>
                <.link navigate="/admin/users" class="link link-primary text-xs">管理用户</.link>
              </div>
              <div class="flex flex-wrap gap-2">
                <.link navigate="/admin/users" class="btn btn-soft btn-primary">
                  <.icon name="hero-user-plus" class="size-4" /> 创建用户
                </.link>
              </div>
            </div>
          </div>
        </div>
      </.admin_shell>
    </Layouts.app>
    """
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
      <table class="table">
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
            <td class="font-medium">{org.name}</td>
            <td><code class="text-xs">{org.slug}</code></td>
            <td><.status_badge status={org.status} /></td>
            <td class="text-right">{plan_label(org.plan)}</td>
          </tr>
          <tr :if={@orgs == []}>
            <td colspan="100%">
              <div class="flex flex-col items-center gap-2 py-8">
                <.icon name="hero-building-office-2" class="size-8 text-base-content/40" />
                <p class="text-sm text-base-content/60">还没有租户，先创建一个吧</p>
                <.link navigate="/admin/tenants" class="btn btn-sm btn-primary">去创建</.link>
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
