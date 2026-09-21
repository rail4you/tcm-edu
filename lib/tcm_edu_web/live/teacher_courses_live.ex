defmodule TcmEduWeb.TeacherCoursesLive do
  @moduledoc """
  Teacher course list at `/teacher/courses`: keyword search, status
  filter tabs with counts, table / card view switch, inline create and
  edit modals, publish / archive / delete with confirmation.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory
  alias TcmEduWeb.CourseCover

  @levels ~w(beginner intermediate advanced)

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    {:ok,
     socket
     |> assign(:page_title, "我的课程")
     |> assign(:page_subtitle, "创建课程 → 上传封面 → 发布，学生即可选课")
     |> assign(:keyword, "")
     |> assign(:status_filter, "all")
     |> assign(:view, "table")
     |> assign(:deleting, nil)
     |> assign(:categories, list_categories(teacher))
     |> assign(:create_modal, false)
     |> assign(:create_form, course_form(%{}))
     |> assign(:edit_modal, false)
     |> assign(:editing, nil)
     |> assign(:edit_form, course_form(%{}))
     |> CourseCover.allow_cover_upload()
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

  def handle_event("open-create", _params, socket) do
    {:noreply,
     socket
     |> assign(:create_modal, true)
     |> assign(:create_form, course_form(%{}))
     |> CourseCover.reset_cover_upload()}
  end

  def handle_event("close-create", _params, socket) do
    {:noreply, socket |> assign(:create_modal, false) |> CourseCover.reset_cover_upload()}
  end

  def handle_event("cancel-cover", %{"ref" => ref}, socket) do
    {:noreply, Phoenix.LiveView.cancel_upload(socket, :cover, ref)}
  end

  def handle_event("validate-create", %{"course" => params}, socket) do
    {:noreply, assign(socket, :create_form, course_form(params))}
  end

  def handle_event("create-course", %{"course" => params}, socket) do
    teacher = socket.assigns.current_teacher
    changeset = course_changeset(params)

    if changeset.valid? do
      get = &Ecto.Changeset.get_field(changeset, &1)

      attrs = %{
        title: get.(:title) |> to_string() |> String.trim(),
        subtitle: get_optional(changeset, :subtitle),
        description: get_optional(changeset, :description),
        level: get_atom(changeset, :level, :beginner),
        price_cents: get_price_cents(changeset),
        teacher_id: teacher.id,
        category_id: get_optional(changeset, :category_id)
      }

      case Course.create_course(attrs, actor: teacher.actor, tenant: teacher.tenant) do
        {:ok, course} ->
          socket =
            case CourseCover.consume_cover(socket, course, teacher) do
              {:ok, _url} ->
                put_flash(socket, :info, "课程《#{course.title}》已创建，封面已上传")

              {:error, message} ->
                put_flash(
                  socket,
                  :info,
                  "课程《#{course.title}》已创建，但封面上传失败（#{message}）"
                )

              :no_entry ->
                put_flash(socket, :info, "课程《#{course.title}》已创建，回到列表继续编辑")
            end

          {:noreply,
           socket
           |> assign(:create_modal, false)
           |> push_navigate(to: "/teacher/courses")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :create_form, Phoenix.Component.to_form(changeset, as: "course"))}
    end
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
      nil ->
        {:noreply, put_flash(socket, :error, "课程不存在")}

      {:error, error} ->
        if to == "publish" do
          {:noreply,
           socket
           |> put_flash(
             :error,
             "还不能发布：至少需要 1 个章节且章节下有 1 个课时，请先添加内容"
           )
           |> load_courses()}
        else
          {:noreply, put_flash(socket, :error, ash_message(error))}
        end
    end
  end

  def handle_event("open-edit", %{"id" => id}, socket) do
    case find_course(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "课程不存在")}

      course ->
        {:noreply,
         socket
         |> assign(
           edit_modal: true,
           editing: course,
           edit_form: course_form(course_to_params(course))
         )
         |> CourseCover.reset_cover_upload()}
    end
  end

  def handle_event("close-edit", _params, socket) do
    {:noreply,
     socket
     |> assign(edit_modal: false, editing: nil)
     |> CourseCover.reset_cover_upload()}
  end

  def handle_event("validate-edit", %{"course" => params}, socket) do
    {:noreply, assign(socket, :edit_form, course_form(params))}
  end

  def handle_event("save-edit", %{"course" => params}, socket) do
    teacher = socket.assigns.current_teacher
    course = socket.assigns.editing
    changeset = course_changeset(params)

    if changeset.valid? do
      get = &Ecto.Changeset.get_field(changeset, &1)

      attrs = %{
        title: get.(:title) |> to_string() |> String.trim(),
        subtitle: get_optional(changeset, :subtitle),
        description: get_optional(changeset, :description),
        level: get_atom(changeset, :level, :beginner),
        price_cents: get_price_cents(changeset),
        category_id: get_optional(changeset, :category_id)
      }

      case course
           |> Ash.Changeset.for_update(:update, attrs,
             actor: teacher.actor,
             tenant: teacher.tenant
           )
           |> Ash.update() do
        {:ok, updated} ->
          socket =
            case CourseCover.consume_cover(socket, updated, teacher) do
              {:ok, _url} ->
                put_flash(socket, :info, "课程信息已保存，封面已更新")

              {:error, message} ->
                put_flash(socket, :info, "课程信息已保存，但封面上传失败（#{message}）")

              :no_entry ->
                put_flash(socket, :info, "课程信息已保存")
            end

          {:noreply,
           socket
           |> assign(edit_modal: false, editing: nil)
           |> load_courses()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :edit_form, Phoenix.Component.to_form(changeset, as: "course"))}
    end
  end

  def handle_event("remove-cover", _params, socket) do
    teacher = socket.assigns.current_teacher

    case CourseCover.remove_cover(socket.assigns.editing, teacher) do
      :ok ->
        socket = load_courses(socket)

        {:noreply,
         socket
         |> assign(:editing, find_course(socket, socket.assigns.editing.id))
         |> put_flash(:info, "封面已移除")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
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

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={@status == :draft} class="badge badge-soft badge-xs badge-ghost">草稿</span>
    <span :if={@status == :published} class="badge badge-soft badge-xs badge-success">已发布</span>
    <span :if={@status == :archived} class="badge badge-soft badge-xs badge-warning">已下架</span>
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
        |> Ash.Query.load([:cover_image_url, :lesson_count, :chapter_count])
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :courses, courses)
  end

  defp can_publish?(course) do
    (course.chapter_count || 0) > 0 and (course.lesson_count || 0) > 0
  end

  defp course_to_params(course) do
    %{
      "title" => course.title,
      "subtitle" => course.subtitle || "",
      "description" => course.description || "",
      "level" => to_string(course.level || :beginner),
      "price_yuan" => if(is_nil(course.price_cents), do: 0, else: course.price_cents / 100),
      "category_id" => course.category_id || ""
    }
  end

  defp level_options, do: [{"初级", "beginner"}, {"中级", "intermediate"}, {"高级", "advanced"}]

  defp list_categories(teacher) do
    case CourseCategory
         |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
         |> Ash.read() do
      {:ok, cats} -> Enum.sort_by(cats, & &1.name)
      _ -> []
    end
  end

  defp course_form(params) do
    params |> course_changeset() |> Phoenix.Component.to_form(as: "course")
  end

  defp course_changeset(params) do
    types = %{
      title: :string,
      subtitle: :string,
      description: :string,
      level: :string,
      price_yuan: :float,
      category_id: :string
    }

    {%{level: "beginner"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:title])
    |> Ecto.Changeset.validate_length(:title, max: 100)
    |> Ecto.Changeset.validate_inclusion(:level, @levels)
    |> Ecto.Changeset.validate_number(:price_yuan, greater_than_or_equal_to: 0)
  end

  defp get_optional(changeset, field) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil -> nil
      "" -> nil
      value when is_binary(value) -> String.trim(value)
      value -> value
    end
  end

  defp get_atom(changeset, field, default) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil -> default
      "" -> default
      value -> String.to_existing_atom(value)
    end
  end

  defp get_price_cents(changeset) do
    case Ecto.Changeset.get_field(changeset, :price_yuan) do
      nil -> 0
      yuan when is_number(yuan) -> round(yuan * 100)
      _ -> 0
    end
  end

  defp ash_message(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(&Exception.message/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("；")
  end

  defp ash_message(%Ash.Error.Forbidden{}) do
    "没有权限执行该操作"
  end

  defp ash_message(error) do
    error
    |> Exception.message()
    |> String.split("\n")
    |> hd()
    |> String.trim()
  end
end
