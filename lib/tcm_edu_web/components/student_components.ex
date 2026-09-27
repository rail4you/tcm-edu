defmodule TcmEduWeb.StudentComponents do
  @moduledoc """
  学员端 storefront 外壳（杏宁树），视觉与管理端/教师端完全区分，并尽量还原
  `/Users/bai/Desktop/public` 里的「人民医学网」商城原型：

    * 白底扁平 header（logo + 纯文本导航 + 绿色登录按钮）
    * 浅灰画布 `bg-[#f5f5f5]`（非管理端的抽屉/工作台外观）
    * 白色 `shadow-sm` 课程卡片，封面上绿色渐变，分类用绿色描边标签，价格橙红
  """
  use Phoenix.Component

  import TcmEduWeb.CoreComponents, only: [icon: 1]

  # Generated TCM-themed placeholder covers (meridian / herbs / yin-yang /
  # scrolls / zang / landscape) used by course_card when a course has no
  # uploaded cover image. The selection is deterministic per course id so a
  # card's cover stays stable across renders.
  @cover_fallbacks ~w(meridian herbs yinyang scrolls zang landscape)

  @doc "Pick a TCM-themed fallback cover URL for a course (stable per id)."
  def cover_for(%{cover_image_url: url}) when is_binary(url) and byte_size(url) > 0, do: url

  def cover_for(%{id: id}) do
    "/images/covers/#{Enum.at(@cover_fallbacks, :erlang.phash2(id, 6))}.jpg"
  end

  def cover_for(_), do: "/images/covers/#{Enum.at(@cover_fallbacks, 0)}.jpg"

  attr :current_student, :map, default: nil
  attr :current_page, :atom, default: :home
  attr :unread_count, :integer, default: 0

  slot :inner_block, required: true

  def student_shell(assigns) do
    ~H"""
    <div
      data-theme="storefront"
      class="flex min-h-screen flex-col bg-[#f5f5f5] text-[#333]"
      id="student-shell"
    >
      <header class="sticky top-0 z-30 border-b border-[#e5e5e5] bg-white/95 backdrop-blur">
        <div class="mx-auto flex h-[68px] w-full max-w-6xl items-center justify-between gap-3 px-4 sm:px-6">
          <div class="flex items-center gap-6">
            <div class="dropdown lg:hidden">
              <button tabindex="0" class="btn btn-square btn-ghost btn-sm" aria-label="打开菜单">
                <.icon name="hero-bars-3" class="size-5" />
              </button>
              <ul
                tabindex="0"
                class="menu dropdown-content z-50 mt-2 w-56 rounded-box bg-base-100 p-2 shadow-md"
              >
                <.mobile_link navigate="/" label="首页" />
                <.mobile_link navigate="/courses" label="精品课程" />
                <.mobile_link navigate="/resources" label="资料下载" />
                <.mobile_link navigate="/my-learning" label="我的学习" />
                <.mobile_link navigate="/exams" label="我的考试" />
                <.mobile_link navigate="/ai-chat" label="AI 聊天" />
                <.mobile_link navigate="/simulated-patient" label="AI 诊疗" />
                <.mobile_link navigate="/mdt" label="多学科会诊" />
              </ul>
            </div>
            <.link navigate="/" class="flex items-center" aria-label="杏宁树首页">
              <img
                src="/images/logo.png"
                alt="杏宁树"
                class="hidden h-9 w-auto sm:block"
              />
              <img src="/images/logo-mark.png" alt="杏宁树" class="h-10 w-auto sm:hidden" />
            </.link>
          </div>

          <nav class="hidden items-center gap-7 text-[15px] lg:flex" aria-label="学员端导航">
            <.nav_link navigate="/" label="首页" active={@current_page == :home} />
            <.nav_link navigate="/courses" label="精品课程" active={@current_page in [:courses, :course]} />
            <.nav_link navigate="/resources" label="资料下载" active={@current_page == :resources} />
            <.nav_link navigate="/my-learning" label="我的学习" active={@current_page in [:my_learning, :mistakes]} />
            <.nav_link navigate="/exams" label="我的考试" active={@current_page == :exams} />
            <.nav_link navigate="/ai-chat" label="AI 聊天" active={@current_page == :ai_chat} />
            <.nav_link navigate="/simulated-patient" label="AI 诊疗" active={@current_page == :simulated_patient} />
            <.nav_link navigate="/mdt" label="多学科会诊" active={@current_page in [:mdt, :mdt_room]} />
          </nav>

          <div class="flex items-center gap-2">
            <div :if={@current_student}>
              <.link navigate="/notifications" class="btn btn-square btn-ghost btn-sm" aria-label="通知中心">
                <span class="indicator">
                  <.icon name="hero-bell" class="size-5" />
                  <span :if={@unread_count > 0} class="indicator-item badge badge-xs badge-error">
                    {@unread_count}
                  </span>
                </span>
              </.link>
              <div class="dropdown dropdown-end">
                <button tabindex="0" class="btn btn-ghost btn-circle btn-sm avatar" aria-label="账户菜单">
                  <span class="flex size-9 items-center justify-center rounded-full bg-[#00b86b] text-sm text-white">
                    {student_initial(@current_student)}
                  </span>
                </button>
                <ul
                  tabindex="0"
                  class="menu dropdown-content z-50 mt-2 w-60 rounded-box border border-base-300 bg-base-100 p-2 shadow-md"
                >
                  <li class="menu-title px-2 pb-1">
                    <span class="text-xs font-normal text-base-content/60">已登录为</span>
                  </li>
                  <li class="menu-title -mt-1 px-2 pb-2">
                    <span class="truncate text-sm font-semibold text-base-content">
                      {@current_student.email}
                    </span>
                  </li>
                  <li>
                    <.link navigate="/my-learning" class="flex items-center gap-2">
                      <.icon name="hero-book-open" class="size-4 shrink-0" />
                      我的学习
                    </.link>
                  </li>
                  <li>
                    <.link
                      href="/logout"
                      method="post"
                      class="flex items-center gap-2 text-error hover:bg-error/10"
                    >
                      <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 shrink-0" />
                      退出登录
                    </.link>
                  </li>
                </ul>
              </div>
            </div>
            <.link
              :if={!@current_student}
              navigate="/login"
              class="rounded bg-[#00b86b] px-5 py-1.5 text-sm text-white transition hover:brightness-95"
            >
              登录
            </.link>
          </div>
        </div>
      </header>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <footer class="mt-10 border-t border-[#e5e5e5] bg-white">
        <div class="mx-auto flex w-full max-w-6xl flex-col items-center gap-3 px-4 py-8 text-xs text-[#888] sm:flex-row sm:justify-between">
          <div class="flex items-center gap-2">
            <img src="/images/logo-mark.png" alt="杏宁树" class="h-6 w-auto" />
            <p>杏宁树 · 中医教学</p>
          </div>
          <div class="flex gap-6">
            <.link navigate="/courses" class="hover:text-[#00b86b]">精品课程</.link>
            <.link navigate="/resources" class="hover:text-[#00b86b]">资料下载</.link>
            <.link navigate="/simulated-patient" class="hover:text-[#00b86b]">AI 诊疗</.link>
          </div>
          <p>系统学中医，从这里开始</p>
        </div>
      </footer>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :label, :string, required: true

  defp mobile_link(assigns) do
    ~H"""
    <li>
      <.link navigate={@navigate} class="w-full">{@label}</.link>
    </li>
    """
  end

  attr :navigate, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={["transition hover:text-[#00b86b]", @active && "font-semibold text-[#00b86b]"]}
    >
      {@label}
    </.link>
    """
  end

  @doc """
  Course card resembling the storefront mockup: white `shadow-sm` card, a
  gradient cover showing the course title, a green-outlined category tag,
  orange price and gray in-study count.
  """
  attr :course, :map, required: true
  attr :id, :string, default: nil
  attr :progress_pct, :integer, default: nil

  # 跨租户不可访问时只给预览：渲染成不可点击的 div，不再 navigate 到详情页
  # （详情页在该租户下会直接报“课程不存在”）。
  attr :preview?, :boolean, default: false

  def course_card(%{preview?: true} = assigns) do
    ~H"""
    <div
      id={@id}
      title="当前校区暂无此课程，仅供预览"
      aria-disabled="true"
      class="group relative block overflow-hidden bg-white shadow-sm"
    >
      <figure class="relative h-32 overflow-hidden bg-[#1a2e2a]">
        <img
          src={cover_for(@course)}
          alt={@course.title}
          loading="lazy"
          class="h-full w-full object-cover opacity-90"
        />
        <div class="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/55 via-transparent to-transparent"></div>
        <span class="absolute bottom-2 left-2 rounded bg-white/85 px-2 py-0.5 text-[11px] font-medium text-[#1a2e2a] backdrop-blur-sm">
          {level_label(@course.level)}
        </span>
        <span class="absolute right-2 top-2 rounded bg-black/60 px-2 py-0.5 text-[11px] font-medium text-white backdrop-blur-sm">
          仅预览
        </span>
      </figure>
      <div class="flex flex-1 flex-col p-3">
        <p class="truncate text-base font-medium">{@course.title}</p>
        <p class="mt-1 truncate text-xs text-[#999]">{@course.subtitle || "杏宁树中医课堂"}</p>
        <div class="mt-2 flex flex-wrap items-center gap-1.5">
          <span :if={category_name(@course.category)} class="inline-block border border-[#00c98a] px-2 py-0.5 text-xs text-[#00b86b]">
            {category_name(@course.category)}
          </span>
          <span class="text-[11px] text-[#bbb]">{@course.lesson_count || 0} 课时</span>
        </div>
        <div :if={@progress_pct} class="mt-3 flex items-center gap-2">
          <progress class="progress progress-success h-1.5 w-full" value={@progress_pct} max="100" />
          <p class="text-xs tabular-nums text-[#999]">{@progress_pct}%</p>
        </div>
        <div class="mt-auto flex items-center justify-between pt-4">
          <b :if={price_label(@course.price_cents)} class="text-xl leading-none text-[#ff4d2f]">{price_label(@course.price_cents)}</b>
          <span class="ml-auto text-xs text-[#999]">{@course.student_count || @course.total_students || 0} 人在学</span>
        </div>
        <p class="mt-2 text-[11px] text-[#bbb]">当前校区暂无此课程，仅供预览</p>
      </div>
    </div>
    """
  end

  def course_card(assigns) do
    ~H"""
    <.link
      navigate={"/courses/#{@course.id}"}
      id={@id}
      class="group block overflow-hidden bg-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
    >
      <figure class="relative h-32 overflow-hidden bg-[#1a2e2a]">
        <img
          src={cover_for(@course)}
          alt={@course.title}
          loading="lazy"
          class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
        />
        <div class="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/55 via-transparent to-transparent"></div>
        <span class="absolute bottom-2 left-2 rounded bg-white/85 px-2 py-0.5 text-[11px] font-medium text-[#1a2e2a] backdrop-blur-sm">
          {level_label(@course.level)}
        </span>
      </figure>
      <div class="flex flex-1 flex-col p-3">
        <p class="truncate text-base font-medium">{@course.title}</p>
        <p class="mt-1 truncate text-xs text-[#999]">{@course.subtitle || "杏宁树中医课堂"}</p>
        <div class="mt-2 flex flex-wrap items-center gap-1.5">
          <span :if={category_name(@course.category)} class="inline-block border border-[#00c98a] px-2 py-0.5 text-xs text-[#00b86b]">
            {category_name(@course.category)}
          </span>
          <span class="text-[11px] text-[#bbb]">{@course.lesson_count || 0} 课时</span>
        </div>
        <div :if={@progress_pct} class="mt-3 flex items-center gap-2">
          <progress class="progress progress-success h-1.5 w-full" value={@progress_pct} max="100" />
          <p class="text-xs tabular-nums text-[#999]">{@progress_pct}%</p>
        </div>
        <div class="mt-auto flex items-center justify-between pt-4">
          <b :if={price_label(@course.price_cents)} class="text-xl leading-none text-[#ff4d2f]">{price_label(@course.price_cents)}</b>
          <span class="ml-auto text-xs text-[#999]">{@course.student_count || @course.total_students || 0} 人在学</span>
        </div>
      </div>
    </.link>
    """
  end

  defp level_label(:beginner), do: "初级"
  defp level_label(:intermediate), do: "中级"
  defp level_label(:advanced), do: "高级"
  defp level_label(_), do: "-"

  defp category_name(%{name: name}), do: name
  defp category_name(_), do: nil

  defp price_label(nil), do: nil
  defp price_label(0), do: nil
  defp price_label(cents), do: "¥#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp student_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(_), do: "学"
end
