defmodule TcmEduWeb.StudentComponents do
  @moduledoc """
  Shared storefront shell for the student portal: sticky top navbar,
  content canvas, minimal footer. Anonymous visitors see a login CTA;
  logged-in students see a notification bell (with unread dot) and an
  account menu.
  """
  use Phoenix.Component

  import TcmEduWeb.CoreComponents, only: [icon: 1]

  attr :current_student, :map, default: nil
  attr :current_page, :atom, default: :home
  attr :unread_count, :integer, default: 0

  slot :inner_block, required: true

  def student_shell(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-base-100">
      <header class="navbar sticky top-0 z-30 border-b border-base-300 bg-base-100/95 backdrop-blur">
        <div class="navbar-start">
          <div class="dropdown lg:hidden">
            <button tabindex="0" class="btn btn-square btn-ghost" aria-label="打开菜单">
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <ul
              tabindex="0"
              class="menu dropdown-content z-50 mt-2 w-52 rounded-box bg-base-100 p-2 shadow-md"
            >
              <.mobile_link navigate="/" label="首页" />
              <.mobile_link navigate="/courses" label="课程" />
              <.mobile_link navigate="/my-learning" label="我的学习" />
              <.mobile_link navigate="/posts" label="交流" />
              <.mobile_link navigate="/chat" label="AI 问答" />
            </ul>
          </div>
          <.link navigate="/" class="flex items-center gap-2">
            <span class="flex size-8 items-center justify-center rounded-full bg-primary text-primary-content">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <p class="font-semibold">中医教学</p>
          </.link>
        </div>
        <nav class="navbar-center hidden gap-1 lg:flex" aria-label="学生端导航">
          <.nav_link navigate="/" label="首页" active={@current_page == :home} />
          <.nav_link navigate="/courses" label="课程" active={@current_page in [:courses, :course]} />
          <.nav_link navigate="/my-learning" label="我的学习" active={@current_page in [:my_learning, :mistakes]} />
          <.nav_link navigate="/posts" label="交流" active={@current_page in [:posts, :post_new]} />
          <.nav_link navigate="/chat" label="AI 问答" active={@current_page == :chat} />
        </nav>
        <div class="navbar-end gap-2">
          <div :if={@current_student}>
            <.link navigate="/notifications" class="btn btn-square btn-ghost" aria-label="通知中心">
              <span class="indicator">
                <.icon name="hero-bell" class="size-5" />
                <span :if={@unread_count > 0} class="indicator-item badge badge-xs badge-error">
                  {@unread_count}
                </span>
              </span>
            </.link>
            <div class="dropdown dropdown-end">
              <button tabindex="0" class="btn btn-ghost btn-circle avatar" aria-label="账户菜单">
                <span class="flex size-10 items-center justify-center rounded-full bg-neutral text-sm text-neutral-content">
                  {student_initial(@current_student)}
                </span>
              </button>
              <ul
                tabindex="0"
                class="menu dropdown-content z-50 mt-2 w-52 rounded-box bg-base-100 p-2 shadow-md"
              >
                <li class="menu-title">
                  <span class="truncate">{@current_student.email}</span>
                </li>
                <li>
                  <.link navigate="/my-learning" class="w-full">
                    <.icon name="hero-book-open" class="size-4" /> 我的学习
                  </.link>
                </li>
                <li>
                  <form action="/logout" method="post" id="student-logout-form" class="contents">
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
          <div :if={!@current_student} class="flex items-center gap-2">
            <.link navigate="/login" class="btn btn-primary btn-sm">登录</.link>
          </div>
        </div>
      </header>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-base-300 bg-base-200/30">
        <div class="mx-auto flex w-full max-w-6xl flex-col items-center gap-2 px-4 py-6 text-xs text-base-content/60 sm:flex-row sm:justify-between">
          <p>中医教学 · 学员端</p>
          <div class="flex gap-4">
            <.link navigate="/courses" class="hover:text-base-content">课程</.link>
            <.link navigate="/posts" class="hover:text-base-content">交流</.link>
            <.link navigate="/chat" class="hover:text-base-content">AI 问答</.link>
          </div>
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
    <.link navigate={@navigate} class={["btn btn-ghost btn-sm", @active && "btn-active"]}>
      {@label}
    </.link>
    """
  end

  @doc "Course card used by home / courses / my-learning pages."
  attr :course, :map, required: true
  attr :id, :string, default: nil
  attr :progress_pct, :integer, default: nil

  def course_card(assigns) do
    ~H"""
    <.link
      navigate={"/courses/#{@course.id}"}
      id={@id}
      class="card group bg-base-100 shadow-sm transition hover:-translate-y-1 hover:shadow-md"
    >
      <figure class="relative aspect-[16/9] overflow-hidden bg-base-200">
        <img
          :if={@course.cover_image_url}
          src={@course.cover_image_url}
          alt={@course.title}
          loading="lazy"
          class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
        />
        <span :if={!@course.cover_image_url} class="flex h-full w-full items-center justify-center text-4xl font-semibold text-primary/60">
          {String.first(@course.title)}
        </span>
      </figure>
      <div class="card-body gap-2 p-4">
        <p class="font-medium leading-snug">{@course.title}</p>
        <p class="line-clamp-2 text-xs text-base-content/60">{@course.subtitle || "暂无简介"}</p>
        <div :if={@progress_pct} class="flex items-center gap-2">
          <progress class="progress progress-success w-full" value={@progress_pct} max="100" />
          <p class="text-xs tabular-nums text-base-content/60">{@progress_pct}%</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <span class="badge badge-soft">{level_label(@course.level)}</span>
          <span class="badge badge-soft badge-info">{@course.lesson_count || 0} 课时</span>
          <span class="badge badge-soft badge-success">{price_label(@course.price_cents)}</span>
        </div>
      </div>
    </.link>
    """
  end

  defp level_label(:beginner), do: "初级"
  defp level_label(:intermediate), do: "中级"
  defp level_label(:advanced), do: "高级"
  defp level_label(_), do: "-"

  defp price_label(nil), do: "-"
  defp price_label(0), do: "免费"
  defp price_label(cents), do: "¥#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp student_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(_), do: "学"
end
