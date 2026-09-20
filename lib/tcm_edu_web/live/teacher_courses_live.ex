defmodule TcmEduWeb.TeacherCoursesLive do
  @moduledoc """
  Teacher course list at `/teacher/courses`: keyword search, status
  filter tabs with counts, table / card view switch, publish / archive /
  delete with confirmation.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "我的课程")
     |> assign(:page_subtitle, "创建课程 → 添加章节与课时 → 发布，学生即可选课")
     |> assign(:keyword, "")
     |> assign(:status_filter, "all")
     |> assign(:view, "table")
     |> assign(:deleting, nil)
     |> load_courses()}
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, assign(socket, :keyword, String.trim(keyword))}
  end

  def handle_event("filter", %{"status" => status}, socket)
      when status in ["all", "draft", "published", "archived"] do
    {:noreply, assign(socket, :status_filter, status)}
  end

  def handle_event("view", %{"view" => view}, socket) when view in ["table", "card"] do
    {:noreply, assign(socket, :view, view)}
  end

  def handle_event("transition", %{"id" => id, "to" => to}, socket)
      when to in ["publish", "archive"] do
    action = String.to_existing_atom(to)
    teacher = socket.assigns.current_teacher

    with course when not is_nil(course) <- find_course(socket, id),
         {:ok, _} <-
           course
           |> Ash.Changeset.for_update(action, %{}, actor: teacher.actor, tenant: teacher.tenant)
           |> Ash.update() do
      message = if to == "publish", do: "已发布", else: "已下架"
      {:noreply, socket |> put_flash(:info, message) |> load_courses()}
    else
      nil -> {:noreply, put_flash(socket, :error, "课程不存在")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("confirm-delete", %{"id" => id}, socket) do
    case find_course(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, "课程不存在")}
      course -> {:noreply, assign(socket, :deleting, course)}
    end
  end

  def handle_event("close-delete", _params, socket) do
    {:noreply, assign(socket, :deleting, nil)}
  end

  def handle_event("delete", _params, socket) do
    teacher = socket.assigns.current_teacher
    course = socket.assigns.deleting

    case Ash.destroy(course, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:deleting, nil)
         |> put_flash(:info, "已删除 #{course.title}")
         |> load_courses()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell
        current_teacher={@current_teacher}
        current_page={:courses}
        page_title="我的课程"
        page_subtitle="创建课程 → 添加章节与课时 → 发布，学生即可选课"
      >
        <:page_actions>
          <.link navigate="/teacher/courses/new" class="btn btn-primary btn-sm" id="new-course-btn">
            <.icon name="hero-plus" class="size-4" /> 创建课程
          </.link>
        </:page_actions>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-4 p-4 sm:p-6">
            <div class="flex flex-wrap items-center gap-2">
              <form phx-change="search" phx-submit="search" class="min-w-52 flex-1">
                <label class="input input-bordered input-sm flex items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-4 text-base-content/60" />
                  <input
                    type="search"
                    name="keyword"
                    value={@keyword}
                    placeholder="搜索课程标题"
                    class="grow"
                    aria-label="搜索课程"
                  />
                </label>
              </form>
              <div class="join" role="tablist" aria-label="视图切换">
                <button
                  class={["btn join-item btn-sm", @view == "table" && "btn-active"]}
                  phx-click="view"
                  phx-value-view="table"
                  aria-label="表格视图"
                >
                  <.icon name="hero-bars-3-bottom-left" class="size-4" />
                </button>
                <button
                  class={["btn join-item btn-sm", @view == "card" && "btn-active"]}
                  phx-click="view"
                  phx-value-view="card"
                  aria-label="卡片视图"
                >
                  <.icon name="hero-squares-2x2" class="size-4" />
                </button>
              </div>
            </div>

            <div class="tabs tabs-boxed w-fit" role="tablist" aria-label="按状态筛选">
              <button
                :for={s <- ["all", "draft", "published", "archived"]}
                role="tab"
                class={["tab", @status_filter == s && "tab-active"]}
                phx-click="filter"
                phx-value-status={s}
              >
                {status_label(s)}（{count_by(@courses, s)}）
              </button>
            </div>

            <div :if={@view == "table"} class="overflow-x-auto rounded-box border border-base-300">
              <table class="table table-zebra table-pin-rows">
                <thead>
                  <tr>
                    <th>课程</th>
                    <th>状态</th>
                    <th>难度</th>
                    <th class="text-right tabular-nums">课时</th>
                    <th class="text-right tabular-nums">价格</th>
                    <th class="text-right">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={course <- visible(@courses, @status_filter, @keyword)} id={"course-#{course.id}"}>
                    <td>
                      <div class="flex items-center gap-3">
                        <span class="avatar">
                          <span class="flex size-10 items-center justify-center overflow-hidden rounded-box bg-base-200">
                            <img
                              :if={course.cover_image_url}
                              src={course.cover_image_url}
                              alt=""
                              loading="lazy"
                              class="h-full w-full object-cover"
                            />
                            <span :if={!course.cover_image_url} class="text-sm font-semibold text-primary">
                              {String.first(course.title)}
                            </span>
                          </span>
                        </span>
                        <div class="min-w-0">
                          <p class="max-w-64 truncate font-medium">{course.title}</p>
                          <p class="max-w-64 truncate text-xs text-base-content/60">{course.subtitle || "暂无简介"}</p>
                        </div>
                      </div>
                    </td>
                    <td><.status_badge status={course.status} /></td>
                    <td>{level_label(course.level)}</td>
                    <td class="text-right tabular-nums">{course.lesson_count || 0}</td>
                    <td class="text-right tabular-nums">{price_label(course.price_cents)}</td>
                    <td>
                      <div class="flex justify-end gap-1">
                        <.link navigate={"/teacher/courses/#{course.id}/edit"} class="btn btn-ghost btn-xs">
                          编辑
                        </.link>
                        <button
                          :if={course.status != :published}
                          class="btn btn-ghost btn-xs"
                          phx-click="transition"
                          phx-value-id={course.id}
                          phx-value-to="publish"
                        >
                          发布
                        </button>
                        <button
                          :if={course.status == :published}
                          class="btn btn-ghost btn-xs"
                          phx-click="transition"
                          phx-value-id={course.id}
                          phx-value-to="archive"
                        >
                          下架
                        </button>
                        <button
                          class="btn btn-ghost btn-xs text-error"
                          phx-click="confirm-delete"
                          phx-value-id={course.id}
                        >
                          删除
                        </button>
                      </div>
                    </td>
                  </tr>
                  <tr :if={visible(@courses, @status_filter, @keyword) == []}>
                    <td colspan="100%">
                      <div class="flex flex-col items-center gap-2 py-8">
                        <.icon name="hero-book-open" class="size-8 text-base-content/40" />
                        <p class="text-sm text-base-content/60">没有匹配的课程</p>
                        <.link navigate="/teacher/courses/new" class="btn btn-sm btn-primary">
                          创建课程
                        </.link>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div :if={@view == "card"} class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              <div
                :for={course <- visible(@courses, @status_filter, @keyword)}
                class="card bg-base-100 shadow-sm transition hover:-translate-y-1 hover:shadow-md"
                id={"course-card-#{course.id}"}
              >
                <figure class="relative aspect-[16/9] overflow-hidden bg-base-200">
                  <img
                    :if={course.cover_image_url}
                    src={course.cover_image_url}
                    alt={course.title}
                    loading="lazy"
                    class="h-full w-full object-cover"
                  />
                  <span :if={!course.cover_image_url} class="flex h-full w-full items-center justify-center text-4xl font-semibold text-primary/60">
                    {String.first(course.title)}
                  </span>
                  <span class="absolute left-2 top-2"><.status_badge status={course.status} /></span>
                </figure>
                <div class="card-body gap-2 p-4">
                  <p class="truncate font-medium">{course.title}</p>
                  <p class="line-clamp-2 min-h-8 text-xs text-base-content/60">{course.subtitle || "暂无简介"}</p>
                  <div class="flex flex-wrap gap-2">
                    <span class="badge badge-soft badge-xs">{level_label(course.level)}</span>
                    <span class="badge badge-soft badge-info badge-xs">{course.lesson_count || 0} 课时</span>
                    <span class="badge badge-soft badge-success badge-xs">{price_label(course.price_cents)}</span>
                  </div>
                  <div class="card-actions justify-end">
                    <.link navigate={"/teacher/courses/#{course.id}/edit"} class="btn btn-ghost btn-xs">
                      编辑
                    </.link>
                    <button
                      :if={course.status != :published}
                      class="btn btn-ghost btn-xs"
                      phx-click="transition"
                      phx-value-id={course.id}
                      phx-value-to="publish"
                    >
                      发布
                    </button>
                    <button
                      :if={course.status == :published}
                      class="btn btn-ghost btn-xs"
                      phx-click="transition"
                      phx-value-id={course.id}
                      phx-value-to="archive"
                    >
                      下架
                    </button>
                  </div>
                </div>
              </div>
              <div :if={visible(@courses, @status_filter, @keyword) == []} class="card bg-base-100 shadow-sm md:col-span-2 xl:col-span-3">
                <div class="card-body items-center gap-2 p-8">
                  <.icon name="hero-book-open" class="size-8 text-base-content/40" />
                  <p class="text-sm text-base-content/60">没有匹配的课程</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div :if={@deleting} class="modal modal-open" role="dialog" aria-modal="true">
          <div class="modal-box">
            <p class="text-lg font-medium">删除课程《{@deleting.title}》？</p>
            <p class="py-2 text-sm text-base-content/60">章节课时将一并删除，该操作不可恢复。</p>
            <div class="modal-action">
              <button type="button" class="btn btn-soft" phx-click="close-delete">取消</button>
              <button type="button" class="btn btn-error" phx-click="delete" id="confirm-delete-btn">
                确认删除
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="close-delete"></div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={@status == :draft} class="badge badge-soft badge-ghost">草稿</span>
    <span :if={@status == :published} class="badge badge-soft badge-success">已发布</span>
    <span :if={@status == :archived} class="badge badge-soft badge-warning">已下架</span>
    """
  end

  defp status_label("all"), do: "全部"
  defp status_label("draft"), do: "草稿"
  defp status_label("published"), do: "已发布"
  defp status_label("archived"), do: "已下架"

  defp level_label(:beginner), do: "初级"
  defp level_label(:intermediate), do: "中级"
  defp level_label(:advanced), do: "高级"
  defp level_label(_), do: "-"

  defp price_label(nil), do: "-"
  defp price_label(0), do: "免费"
  defp price_label(cents), do: "¥#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp count_by(courses, "all"), do: length(courses)
  defp count_by(courses, status), do: Enum.count(courses, &(to_string(&1.status) == status))

  defp visible(courses, status_filter, keyword) do
    courses
    |> filtered(status_filter)
    |> filter_keyword(keyword)
  end

  defp filtered(courses, "all"), do: courses
  defp filtered(courses, status), do: Enum.filter(courses, &(to_string(&1.status) == status))

  defp filter_keyword(courses, ""), do: courses

  defp filter_keyword(courses, keyword) do
    kw = String.downcase(keyword)

    Enum.filter(courses, fn course ->
      String.contains?(String.downcase("#{course.title} #{course.subtitle || ""}"), kw)
    end)
  end

  defp find_course(socket, id), do: Enum.find(socket.assigns.courses, &(&1.id == id))

  defp load_courses(socket) do
    teacher = socket.assigns.current_teacher

    courses =
      try do
        Course
        |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.Query.load([:lesson_count])
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :courses, courses)
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
