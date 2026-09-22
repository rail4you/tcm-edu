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

  attr :current_page, :atom,
    required: true,
    values: [:dashboard, :tenants, :users, :knowledge, :ai_dashboard, :ai_keys, :login]

  attr :page_title, :string, default: "工作台"

  slot :inner_block, required: true
  slot :page_actions

  def admin_shell(assigns) do
    ~H"""
    <div
      id="admin-shell"
      class="drawer lg:drawer-open h-screen w-full overflow-hidden"
      phx-hook="SidebarCollapse"
      data-collapse-key="tcm-admin-sidebar"
    >
      <input id="admin-drawer" type="checkbox" class="drawer-toggle" phx-update="ignore" />
      <script>
        (function () {
          try {
            var t = document.getElementById("admin-drawer");
            if (window.innerWidth >= 1024) {
              var shell = t.closest("[data-collapse-key]");
              var key = (shell && shell.dataset.collapseKey) || "tcm-admin-sidebar";
              var saved = localStorage.getItem(key);
              t.checked = saved === null ? true : saved === "1";
            }
          } catch (e) {}
        })();
      </script>

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
        <aside class="flex min-h-full w-60 flex-col bg-base-100 transition-all duration-200 lg:is-drawer-open:w-64 lg:is-drawer-close:w-16">
          <div class="flex h-16 shrink-0 items-center gap-2 border-b border-base-300 px-4 lg:is-drawer-close:justify-center lg:is-drawer-close:px-2">
            <img
              src="/images/logo-mark.png"
              alt="杏宁树"
              class="size-8 shrink-0 rounded-full object-cover"
            />
            <div class="min-w-0 lg:is-drawer-close:hidden">
              <p class="text-sm font-semibold leading-tight">杏宁树 · 中医教学</p>
              <p class="text-xs text-base-content/60">管理端</p>
            </div>
          </div>
          <.sidebar_menu current_admin={@current_admin} current_page={@current_page} />
          <div class="mt-auto border-t border-base-300 p-4 lg:is-drawer-close:flex lg:is-drawer-close:justify-center lg:is-drawer-close:p-2">
            <div class="flex items-center gap-2">
              <span class="avatar avatar-placeholder shrink-0">
                <span class="flex size-10 items-center justify-center rounded-full bg-neutral text-sm text-neutral-content">
                  {admin_initial(@current_admin)}
                </span>
              </span>
              <div class="min-w-0 lg:is-drawer-close:hidden">
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
    <header class="navbar h-16 shrink-0 gap-2 border-b border-base-300 bg-base-100 px-4">
      <div class="flex-none lg:hidden">
        <label for="admin-drawer" class="btn btn-square btn-ghost" aria-label="打开菜单">
          <.icon name="hero-bars-3" class="size-5" />
        </label>
      </div>
      <div class="flex-none hidden lg:flex">
        <label for="admin-drawer" class="btn btn-square btn-ghost" aria-label="收起或展开侧边栏">
          <.icon name="hero-bars-3-bottom-left" class="size-5" />
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
        <.theme_menu portal={:admin} default_theme="light" />
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
              <form action="/logout" method="post" id="admin-logout-form" class="contents">
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

  attr :portal, :atom, required: true
  attr :default_theme, :string, default: "light"

  defp theme_menu(assigns) do
    ~H"""
    <div
      id={"theme-menu-#{@portal}"}
      class="dropdown dropdown-end"
      phx-hook="ThemeController"
      data-default-theme={@default_theme}
    >
      <button tabindex="0" type="button" class="btn btn-ghost btn-sm" aria-label="切换主题">
        <.icon name="hero-swatch" class="size-4" />
        <span class="hidden sm:inline">主题</span>
      </button>
      <div
        tabindex="0"
        class="dropdown-content z-50 mt-2 w-44 rounded-box bg-base-100 p-2 shadow-md"
      >
        <p class="px-3 py-1 text-xs text-base-content/60">切换主题</p>
        <label class="flex cursor-pointer items-center gap-2 rounded-field px-3 py-2 hover:bg-base-200">
          <input type="radio" name={"theme-#{@portal}"} value="light" class="theme-controller" />
          浅色
        </label>
        <label class="flex cursor-pointer items-center gap-2 rounded-field px-3 py-2 hover:bg-base-200">
          <input type="radio" name={"theme-#{@portal}"} value="dark" class="theme-controller" />
          深色
        </label>
        <label class="flex cursor-pointer items-center gap-2 rounded-field px-3 py-2 hover:bg-base-200">
          <input type="radio" name={"theme-#{@portal}"} value="tcm" class="theme-controller" />
          中医蓝
        </label>
        <label class="flex cursor-pointer items-center gap-2 rounded-field px-3 py-2 hover:bg-base-200">
          <input type="radio" name={"theme-#{@portal}"} value="business" class="theme-controller" />
          商务暗色
        </label>
      </div>
    </div>
    """
  end

  attr :current_admin, :map, required: true
  attr :current_page, :atom, required: true

  defp sidebar_menu(assigns) do
    ~H"""
    <nav class="flex-1 overflow-y-auto p-4 lg:is-drawer-close:p-2" aria-label="管理端导航">
      <ul class="menu w-full gap-1 lg:is-drawer-close:hidden">
        <li>
          <details open={@current_page in [:dashboard]}>
            <summary>
              <.icon name="hero-squares-2x2" class="size-4" />
              <span>总览</span>
            </summary>
            <ul>
              <li>
                <.link navigate="/admin" class={["w-full", @current_page == :dashboard && "menu-active"]}>
                  <.icon name="hero-squares-2x2" class="size-4" />
                  工作台
                </.link>
              </li>
            </ul>
          </details>
        </li>
        <li :if={@current_admin.role == "super_admin"}>
          <details open={@current_page == :tenants}>
            <summary>
              <.icon name="hero-building-office-2" class="size-4" />
              <span>平台运营</span>
            </summary>
            <ul>
              <li>
                <.link
                  navigate="/admin/tenants"
                  class={["w-full", @current_page == :tenants && "menu-active"]}
                >
                  <.icon name="hero-building-office-2" class="size-4" />
                  租户管理
                </.link>
              </li>
            </ul>
          </details>
        </li>
        <li>
          <details open={@current_page in [:users, :knowledge]}>
            <summary>
              <.icon name="hero-users" class="size-4" />
              <span>本机构</span>
            </summary>
            <ul>
              <li>
                <.link navigate="/admin/users" class={["w-full", @current_page == :users && "menu-active"]}>
                  <.icon name="hero-users" class="size-4" />
                  用户管理
                </.link>
              </li>
              <li>
                <.link
                  navigate="/admin/knowledge"
                  class={["w-full", @current_page == :knowledge && "menu-active"]}
                >
                  <.icon name="hero-bookmark" class="size-4" />
                  知识库
                </.link>
              </li>
            </ul>
          </details>
        </li>
        <li :if={@current_admin.role == "super_admin"}>
          <details open={@current_page in [:ai_dashboard, :ai_keys]}>
            <summary>
              <.icon name="hero-sparkles" class="size-4" />
              <span>AI 能力</span>
            </summary>
            <ul>
              <li>
                <.link
                  navigate="/admin/ai-dashboard"
                  class={["w-full", @current_page == :ai_dashboard && "menu-active"]}
                >
                  <.icon name="hero-squares-2x2" class="size-4" />
                  AI 驾驶舱
                </.link>
              </li>
              <li>
                <.link
                  navigate="/admin/ai-keys"
                  class={["w-full", @current_page == :ai_keys && "menu-active"]}
                >
                  <.icon name="hero-key" class="size-4" />
                  AI Key 管理
                </.link>
              </li>
            </ul>
          </details>
        </li>
      </ul>

      <ul class="menu w-full gap-1 lg:is-drawer-open:hidden">
        <li>
          <.link
            navigate="/admin"
            class={["tooltip tooltip-right w-full", @current_page == :dashboard && "menu-active"]}
            data-tip="工作台"
          >
            <.icon name="hero-squares-2x2" class="size-4" />
          </.link>
        </li>
        <li :if={@current_admin.role == "super_admin"}>
          <.link
            navigate="/admin/tenants"
            class={["tooltip tooltip-right w-full", @current_page == :tenants && "menu-active"]}
            data-tip="租户管理"
          >
            <.icon name="hero-building-office-2" class="size-4" />
          </.link>
        </li>
        <li>
          <.link
            navigate="/admin/users"
            class={["tooltip tooltip-right w-full", @current_page == :users && "menu-active"]}
            data-tip="用户管理"
          >
            <.icon name="hero-users" class="size-4" />
          </.link>
        </li>
        <li>
          <.link
            navigate="/admin/knowledge"
            class={["tooltip tooltip-right w-full", @current_page == :knowledge && "menu-active"]}
            data-tip="知识库"
          >
            <.icon name="hero-bookmark" class="size-4" />
          </.link>
        </li>
        <li :if={@current_admin.role == "super_admin"}>
          <.link
            navigate="/admin/ai-dashboard"
            class={["tooltip tooltip-right w-full", @current_page == :ai_dashboard && "menu-active"]}
            data-tip="AI 驾驶舱"
          >
            <.icon name="hero-sparkles" class="size-4" />
          </.link>
        </li>
        <li :if={@current_admin.role == "super_admin"}>
          <.link
            navigate="/admin/ai-keys"
            class={["tooltip tooltip-right w-full", @current_page == :ai_keys && "menu-active"]}
            data-tip="AI Key 管理"
          >
            <.icon name="hero-key" class="size-4" />
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
