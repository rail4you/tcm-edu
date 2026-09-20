defmodule TcmEduWeb.AdminComponents do
  @moduledoc """
  Shared shell for the LiveView admin panel.

  Follows the daisyUI dashboard skill:

    * root uses `h-screen w-full overflow-hidden` (daisyUI drawer)
    * sidebar is fixed `w-60`/`w-64`, never scrolls; brand row is `h-16` to
      align with the `h-16` topbar
    * main canvas scrolls independently (`flex-1 overflow-y-auto`) on a
      minimal `bg-base-200/10` background, with a minimal footer pinned to
      its bottom
    * navigation uses plain daisyUI `menu` classes; only `menu-active`
      marks the current page
  """
  use Phoenix.Component

  import TcmEduWeb.CoreComponents, only: [icon: 1]

  attr :current_admin, :map, required: true
  attr :current_page, :atom, required: true, values: [:dashboard, :tenants, :users, :login]
  attr :page_title, :string, default: "工作台"

  slot :inner_block, required: true
  slot :page_actions

  def admin_shell(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open h-screen w-full overflow-hidden">
      <input id="admin-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex min-w-0 flex-col">
        <.topbar
          current_admin={@current_admin}
          page_title={@page_title}
          current_page={@current_page}
        />
        <main class="flex-1 overflow-y-auto bg-base-200/10">
          <div class="mx-auto flex min-h-full w-full max-w-6xl flex-col gap-6 p-4 lg:p-6">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div>
                <p class="text-xl font-semibold">{@page_title}</p>
                <div class="breadcrumbs text-xs text-base-content/60">
                  <ul>
                    <li>管理端</li>
                    <li>{@page_title}</li>
                  </ul>
                </div>
              </div>
              <div :if={@page_actions != []} class="flex items-center gap-2">
                {render_slot(@page_actions)}
              </div>
            </div>

            {render_slot(@inner_block)}

            <footer class="mt-auto flex items-center justify-between pt-4 text-xs text-base-content/60">
              <p>中医教学 · 管理端</p>
              <p>LiveView + daisyUI</p>
            </footer>
          </div>
        </main>
      </div>

      <div class="drawer-side z-40">
        <label for="admin-drawer" aria-label="关闭菜单" class="drawer-overlay"></label>
        <aside class="flex min-h-full w-60 flex-col bg-base-100 lg:w-64">
          <div class="flex h-16 items-center gap-2 border-b border-base-300 px-4">
            <span class="flex size-8 items-center justify-center rounded-full bg-primary text-primary-content">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <div>
              <p class="text-sm font-semibold leading-tight">中医教学</p>
              <p class="text-xs text-base-content/60">管理端</p>
            </div>
          </div>
          <.sidebar_menu current_admin={@current_admin} current_page={@current_page} />
          <div class="mt-auto border-t border-base-300 p-4">
            <div class="flex items-center gap-2">
              <span class="avatar avatar-placeholder">
                <span class="flex size-10 items-center justify-center rounded-full bg-neutral text-sm text-neutral-content">
                  {admin_initial(@current_admin)}
                </span>
              </span>
              <div class="min-w-0">
                <p class="truncate text-sm">{@current_admin.name}</p>
                <p class="text-xs text-base-content/60">{role_label(@current_admin.role)}</p>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :current_admin, :map, required: true
  attr :page_title, :string, required: true
  attr :current_page, :atom, required: true

  defp topbar(assigns) do
    ~H"""
    <header class="navbar h-16 border-b border-base-300 bg-base-100">
      <div class="flex-none lg:hidden">
        <label for="admin-drawer" class="btn btn-square btn-ghost" aria-label="打开菜单">
          <.icon name="hero-bars-3" class="size-5" />
        </label>
      </div>
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm">{@page_title}</p>
      </div>
      <div class="flex-none items-center gap-2">
        <span class="badge badge-soft badge-info hidden sm:inline-flex">
          {@current_admin.tenant}
        </span>
        <span class={[
          "badge badge-soft",
          @current_admin.role == "super_admin" && "badge-secondary",
          @current_admin.role != "super_admin" && "badge-primary"
        ]}>
          {role_label(@current_admin.role)}
        </span>
        <div class="dropdown dropdown-end">
          <button tabindex="0" class="btn btn-ghost btn-circle avatar" aria-label="账户菜单">
            <span class="flex size-10 items-center justify-center rounded-full bg-neutral text-sm text-neutral-content">
              {admin_initial(@current_admin)}
            </span>
          </button>
          <ul
            tabindex="0"
            class="menu dropdown-content z-50 mt-2 w-52 rounded-box bg-base-100 p-2 shadow-md"
          >
            <li class="menu-title">
              <span class="truncate">{@current_admin.email}</span>
            </li>
            <li>
              <form action="/admin/logout" method="post" id="admin-logout-form" class="contents">
                <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                <button type="submit" class="w-full text-error hover:bg-error/10">
                  <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
                  退出登录
                </button>
              </form>
            </li>
          </ul>
        </div>
      </div>
    </header>
    """
  end

  attr :current_admin, :map, required: true
  attr :current_page, :atom, required: true

  defp sidebar_menu(assigns) do
    ~H"""
    <nav class="flex-1 overflow-y-auto p-4" aria-label="管理端导航">
      <ul class="menu w-full gap-1">
        <li class="menu-title"><span>总览</span></li>
        <li>
          <.link navigate="/admin" class={["w-full", @current_page == :dashboard && "menu-active"]}>
            <.icon name="hero-squares-2x2" class="size-4" />
            工作台
          </.link>
        </li>
        <li :if={@current_admin.role == "super_admin"} class="menu-title">
          <span>平台运营</span>
        </li>
        <li :if={@current_admin.role == "super_admin"}>
          <.link
            navigate="/admin/tenants"
            class={["w-full", @current_page == :tenants && "menu-active"]}
          >
            <.icon name="hero-building-office-2" class="size-4" />
            租户管理
          </.link>
        </li>
        <li class="menu-title"><span>本机构</span></li>
        <li>
          <.link navigate="/admin/users" class={["w-full", @current_page == :users && "menu-active"]}>
            <.icon name="hero-users" class="size-4" />
            用户管理
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  defp role_label("super_admin"), do: "超级管理员"
  defp role_label("tenant_admin"), do: "租户管理员"
  defp role_label(_), do: "管理员"

  defp admin_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp admin_initial(_), do: "A"
end
