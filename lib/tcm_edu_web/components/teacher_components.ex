defmodule TcmEduWeb.TeacherComponents do
  @moduledoc """
  Shared shell for the LiveView teacher portal, Nexus-style.

  The shell defaults to the custom brand theme (`tcm`) but is fully
  theme-switchable via the topbar theme menu (`ThemeController` hook).
  Structure follows the dashboard skill: `h-screen` drawer with a fixed
  `w-60`/`w-64` sidebar (collapsible to `w-16` icon rail on desktop via the
  daisyUI `is-drawer-open/close` variants), an independently scrolling
  canvas, and a minimal footer. Navigation is grouped into collapsible
  multi-level menu groups highlighted via `menu-active`.
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
    <div
      id="teacher-shell"
      class="drawer lg:drawer-open h-screen w-full overflow-hidden"
      phx-hook="SidebarCollapse"
      data-collapse-key="tcm-teacher-sidebar"
    >
      <input id="teacher-drawer" type="checkbox" class="drawer-toggle" phx-update="ignore" />
      <script>
        (function () {
          try {
            var t = document.getElementById("teacher-drawer");
            if (window.innerWidth >= 1024) {
              var shell = t.closest("[data-collapse-key]");
              var key = (shell && shell.dataset.collapseKey) || "tcm-teacher-sidebar";
              var saved = localStorage.getItem(key);
              t.checked = saved === null ? true : saved === "1";
            }
          } catch (e) {}
        })();
      </script>

      <div class="drawer-content flex min-w-0 flex-col bg-base-200/10">
        <header class="navbar h-16 shrink-0 gap-2 border-b border-base-300 bg-base-100 px-4">
          <div class="flex-none lg:hidden">
            <label for="teacher-drawer" class="btn btn-square btn-ghost btn-sm" aria-label="打开菜单">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>
          <div class="flex-none hidden lg:flex">
            <label for="teacher-drawer" class="btn btn-square btn-ghost btn-sm" aria-label="收起或展开侧边栏">
              <.icon name="hero-bars-3-bottom-left" class="size-5" />
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
            <.theme_menu portal={:teacher} default_theme="tcm" />
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
                  <.link href="/logout" class="flex w-full items-center gap-2 text-error hover:bg-error/10">
                    <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
                    退出登录
                  </.link>
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
        <aside class="flex min-h-full w-60 flex-col bg-neutral text-neutral-content transition-all duration-200 lg:is-drawer-open:w-64 lg:is-drawer-close:w-16">
          <div class="flex h-16 shrink-0 items-center gap-2 border-b border-white/10 px-4 lg:is-drawer-close:justify-center lg:is-drawer-close:px-2">
            <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <div class="min-w-0 lg:is-drawer-close:hidden">
              <p class="text-sm font-semibold leading-tight text-white">中医教学</p>
              <p class="text-xs text-neutral-content/60">教师端</p>
            </div>
          </div>
          <nav class="flex-1 overflow-y-auto p-4 lg:is-drawer-close:p-2" aria-label="教师端导航">
            <ul class="menu w-full gap-1 lg:is-drawer-close:hidden">
              <li>
                <details open={@current_page in [:dashboard, :courses, :quiz, :exams]}>
                  <summary>
                    <.icon name="hero-book-open" class="size-4" />
                    <span>教学</span>
                  </summary>
                  <ul>
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
                    <li>
                      <.link
                        navigate="/teacher/quiz"
                        class={["w-full", @current_page == :quiz && "menu-active"]}
                      >
                        <.icon name="hero-archive-box" class="size-4" />
                        题库管理
                      </.link>
                    </li>
                    <li>
                      <.link
                        navigate="/teacher/exams"
                        class={["w-full", @current_page == :exams && "menu-active"]}
                      >
                        <.icon name="hero-clipboard-document-list" class="size-4" />
                        考试管理
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
              <li>
                <details open={@current_page in [:ai_lesson, :ai_image, :ai_quiz, :ai_jobs]}>
                  <summary>
                    <.icon name="hero-academic-cap" class="size-4" />
                    <span>智慧课程</span>
                  </summary>
                  <ul>
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
                    <li>
                      <.link
                        navigate="/teacher/ai/quiz"
                        class={["w-full", @current_page == :ai_quiz && "menu-active"]}
                      >
                        <.icon name="hero-clipboard-document-list" class="size-4" />
                        AI 出题
                      </.link>
                    </li>
                    <li>
                      <.link
                        navigate="/teacher/ai/jobs"
                        class={["w-full", @current_page == :ai_jobs && "menu-active"]}
                      >
                        <.icon name="hero-queue-list" class="size-4" />
                        AI 任务管理
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
              <li>
                <details open={@current_page in [:ai_chat, :ai_simulated_patient, :mdt]}>
                  <summary>
                    <.icon name="hero-heart" class="size-4" />
                    <span>智慧医疗</span>
                  </summary>
                  <ul>
                    <li>
                      <.link
                        navigate="/teacher/ai/chat"
                        class={["w-full", @current_page == :ai_chat && "menu-active"]}
                      >
                        <.icon name="hero-chat-bubble-left-right" class="size-4" />
                        AI 问答
                      </.link>
                    </li>
                    <li>
                      <.link
                        navigate="/teacher/ai/simulated-patient"
                        class={["w-full", @current_page == :ai_simulated_patient && "menu-active"]}
                      >
                        <.icon name="hero-user-group" class="size-4" />
                        AI 模拟诊疗
                      </.link>
                    </li>
                    <li>
                      <.link
                        navigate="/teacher/mdt"
                        class={["w-full", @current_page == :mdt && "menu-active"]}
                      >
                        <.icon name="hero-chat-bubble-oval-left-ellipsis" class="size-4" />
                        MDT 会诊
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
              <li>
                <details open={@current_page in [:ai_knowledge, :ai_knowledge_qa]}>
                  <summary>
                    <.icon name="hero-bookmark" class="size-4" />
                    <span>知识库</span>
                  </summary>
                  <ul>
                    <li>
                      <.link
                        navigate="/teacher/ai/knowledge"
                        class={["w-full", @current_page == :ai_knowledge && "menu-active"]}
                      >
                        <.icon name="hero-bookmark" class="size-4" />
                        我的知识库
                      </.link>
                    </li>
                    <li>
                      <.link
                        navigate="/teacher/ai/knowledge/qa"
                        class={["w-full", @current_page == :ai_knowledge_qa && "menu-active"]}
                      >
                        <.icon name="hero-chat-bubble-left-right" class="size-4" />
                        知识库问答
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
              <li>
                <details open={@current_page == :students}>
                  <summary>
                    <.icon name="hero-users" class="size-4" />
                    <span>学员</span>
                  </summary>
                  <ul>
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
                </details>
              </li>
            </ul>

            <ul class="menu w-full gap-1 lg:is-drawer-open:hidden">
              <li>
                <.link
                  navigate="/teacher"
                  class={["tooltip tooltip-right w-full", @current_page == :dashboard && "menu-active"]}
                  data-tip="工作台"
                >
                  <.icon name="hero-squares-2x2" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/courses"
                  class={["tooltip tooltip-right w-full", @current_page == :courses && "menu-active"]}
                  data-tip="我的课程"
                >
                  <.icon name="hero-book-open" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/quiz"
                  class={["tooltip tooltip-right w-full", @current_page == :quiz && "menu-active"]}
                  data-tip="题库管理"
                >
                  <.icon name="hero-archive-box" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/exams"
                  class={["tooltip tooltip-right w-full", @current_page == :exams && "menu-active"]}
                  data-tip="考试管理"
                >
                  <.icon name="hero-clipboard-document-list" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/lesson-plan"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_lesson && "menu-active"]}
                  data-tip="AI 备课"
                >
                  <.icon name="hero-sparkles" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/image"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_image && "menu-active"]}
                  data-tip="AI 配图"
                >
                  <.icon name="hero-photo" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/quiz"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_quiz && "menu-active"]}
                  data-tip="AI 出题"
                >
                  <.icon name="hero-clipboard-document-list" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/jobs"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_jobs && "menu-active"]}
                  data-tip="AI 任务管理"
                >
                  <.icon name="hero-queue-list" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/chat"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_chat && "menu-active"]}
                  data-tip="AI 问答"
                >
                  <.icon name="hero-chat-bubble-left-right" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/simulated-patient"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_simulated_patient && "menu-active"]}
                  data-tip="AI 模拟诊疗"
                >
                  <.icon name="hero-user-group" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/mdt"
                  class={["tooltip tooltip-right w-full", @current_page == :mdt && "menu-active"]}
                  data-tip="MDT 会诊"
                >
                  <.icon name="hero-chat-bubble-oval-left-ellipsis" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/knowledge"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_knowledge && "menu-active"]}
                  data-tip="知识库"
                >
                  <.icon name="hero-bookmark" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/ai/knowledge/qa"
                  class={["tooltip tooltip-right w-full", @current_page == :ai_knowledge_qa && "menu-active"]}
                  data-tip="知识库问答"
                >
                  <.icon name="hero-chat-bubble-left-right" class="size-4" />
                </.link>
              </li>
              <li>
                <.link
                  navigate="/teacher/students"
                  class={["tooltip tooltip-right w-full", @current_page == :students && "menu-active"]}
                  data-tip="我的学生"
                >
                  <.icon name="hero-users" class="size-4" />
                </.link>
              </li>
            </ul>
          </nav>
          <div class="mt-auto border-t border-white/10 p-4 lg:is-drawer-close:flex lg:is-drawer-close:justify-center lg:is-drawer-close:p-2">
            <div class="flex items-center gap-2">
              <span class="avatar avatar-placeholder shrink-0">
                <span class="flex size-10 items-center justify-center rounded-full bg-primary text-sm text-primary-content">
                  {teacher_initial(@current_teacher)}
                </span>
              </span>
              <div class="min-w-0 lg:is-drawer-close:hidden">
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

  defp teacher_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp teacher_initial(_), do: "T"
end
