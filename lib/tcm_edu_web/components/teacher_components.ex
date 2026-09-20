defmodule TcmEduWeb.TeacherComponents do
  @moduledoc """
  Shared shell for the LiveView teacher portal, Nexus-style.

  The shell root carries `data-theme="tcm"` so the teacher portal uses
  the custom brand theme while other portals stay on light. Structure
  follows the dashboard skill: `h-screen` drawer, fixed `w-60`/`w-64`
  sidebar with an `h-16` brand row aligned to the `h-16` topbar, an
  independently scrolling canvas, and a minimal footer. The sidebar
  uses the theme's dark neutral surface; navigation highlights only
  via `menu-active`.
  """
  use Phoenix.Component

  import TcmEduWeb.CoreComponents, only: [icon: 1]

  attr :current_teacher, :map, required: true
  attr :current_page, :atom, required: true
  attr :page_title, :string, default: "工作台"
  attr :page_subtitle, :string, default: nil

  slot :inner_block, required: true
  slot :page_actions

  def teacher_shell(assigns) do
    ~H"""
    <div data-theme="tcm" class="drawer lg:drawer-open h-screen w-full overflow-hidden">
      <input id="teacher-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex min-w-0 flex-col bg-base-200/10">
        <header class="navbar h-16 shrink-0 gap-2 border-b border-base-300 bg-base-100 px-4">
          <div class="flex-none lg:hidden">
            <label for="teacher-drawer" class="btn btn-square btn-ghost btn-sm" aria-label="打开菜单">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>
          <div class="min-w-0 flex-1">
            <div class="breadcrumbs text-xs text-base-content/60">
              <ul>
                <li>教师端</li>
                <li class="font-medium text-base-content">{@page_title}</li>
              </ul>
            </div>
          </div>
          <div class="flex-none items-center gap-2">
            <span class="badge badge-soft badge-info hidden md:inline-flex">
              {@current_teacher.tenant}
            </span>
            <span class="badge badge-soft badge-primary hidden sm:inline-flex">
              {if @current_teacher.role == "tenant_admin", do: "机构管理员", else: "教师"}
            </span>
            <div class="dropdown dropdown-end">
              <button tabindex="0" class="btn btn-ghost btn-circle avatar" aria-label="账户菜单">
                <span class="flex size-9 items-center justify-center rounded-full bg-primary text-sm text-primary-content">
                  {teacher_initial(@current_teacher)}
                </span>
              </button>
              <ul
                tabindex="0"
                class="menu dropdown-content z-50 mt-2 w-52 rounded-box bg-base-100 p-2 shadow-md"
              >
                <li class="menu-title">
                  <span class="truncate">{@current_teacher.email}</span>
                </li>
                <li>
                  <form action="/logout" method="post" id="teacher-logout-form" class="contents">
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

        <main class="flex-1 overflow-y-auto">
          <div class="mx-auto flex min-h-full w-full max-w-6xl flex-col gap-6 p-4 lg:p-6">
            <div class="flex flex-wrap items-end justify-between gap-4">
              <div>
                <p class="text-xl font-semibold">{@page_title}</p>
                <p :if={@page_subtitle} class="mt-1 text-sm text-base-content/60">{@page_subtitle}</p>
              </div>
              <div :if={@page_actions != []} class="flex flex-wrap items-center gap-2">
                {render_slot(@page_actions)}
              </div>
            </div>

            {render_slot(@inner_block)}

            <footer class="mt-auto flex items-center justify-between pt-4 text-xs text-base-content/60">
              <p>中医教学 · 教师端</p>
              <p>LiveView + daisyUI</p>
            </footer>
          </div>
        </main>
      </div>

      <div class="drawer-side z-40">
        <label for="teacher-drawer" aria-label="关闭菜单" class="drawer-overlay"></label>
        <aside class="flex min-h-full w-60 flex-col bg-neutral text-neutral-content lg:w-64">
          <div class="flex h-16 shrink-0 items-center gap-2 border-b border-white/10 px-4">
            <span class="flex size-9 items-center justify-center rounded-full bg-primary text-primary-content">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <div>
              <p class="text-sm font-semibold leading-tight text-white">中医教学</p>
              <p class="text-xs text-neutral-content/60">教师端</p>
            </div>
          </div>
          <nav class="flex-1 overflow-y-auto p-4" aria-label="教师端导航">
            <ul class="menu w-full gap-1">
              <li class="menu-title text-neutral-content/50"><span>教学</span></li>
              <li>
                <.link navigate="/teacher" class={["w-full", @current_page == :dashboard && "menu-active"]}>
                  <.icon name="hero-squares-2x2" class="size-4" />
                  工作台
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/courses"
                  class={["w-full", @current_page == :courses && "menu-active"]}
                >
                  <.icon name="hero-book-open" class="size-4" />
                  我的课程
                </.link>
              </li>
              <li class="menu-title text-neutral-content/50"><span>智能备课</span></li>
              <li>
                <.link
                  navigate="/teacher/ai/lesson-plan"
                  class={["w-full", @current_page == :ai_lesson && "menu-active"]}
                >
                  <.icon name="hero-sparkles" class="size-4" />
                  AI 备课
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/image"
                  class={["w-full", @current_page == :ai_image && "menu-active"]}
                >
                  <.icon name="hero-photo" class="size-4" />
                  AI 配图
                </.link>
              </li>
              <li class="menu-title text-neutral-content/50"><span>学员</span></li>
              <li>
                <.link
                  navigate="/teacher/students"
                  class={["w-full", @current_page == :students && "menu-active"]}
                >
                  <.icon name="hero-users" class="size-4" />
                  我的学生
                </.link>
              </li>
            </ul>
          </nav>
          <div class="mt-auto border-t border-white/10 p-4">
            <div class="flex items-center gap-2">
              <span class="avatar avatar-placeholder">
                <span class="flex size-10 items-center justify-center rounded-full bg-primary text-sm text-primary-content">
                  {teacher_initial(@current_teacher)}
                </span>
              </span>
              <div class="min-w-0">
                <p class="truncate text-sm text-white">{@current_teacher.name}</p>
                <p class="truncate text-xs text-neutral-content/60">{@current_teacher.email}</p>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  defp teacher_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp teacher_initial(_), do: "T"
end
