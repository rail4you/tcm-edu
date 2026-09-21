defmodule TcmEduWeb.TeacherCourseEditLive do
  @moduledoc """
  Course editor at `/teacher/courses/:id/edit`.

  Basic info form, publish/archive actions, and full chapter/lesson
  management (create, rename, delete with confirmation) rendered as
  daisyUI collapses.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Courses.Chapter
  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory
  alias TcmEdu.Courses.Lesson

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @levels ~w(beginner intermediate advanced)
  @content_types ~w(video article pdf)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "编辑课程")
      |> assign(:course_id, id)
      |> assign(:course, nil)
      |> assign(:not_found, false)
      |> assign(:categories, list_categories(socket.assigns.current_teacher))
      |> assign(:basic_form, course_form(%{}))
      |> assign(:chapter_modal, nil)
      |> assign(:chapter_editing, nil)
      |> assign(:chapter_form, chapter_form(%{}))
      |> assign(:lesson_modal, nil)
      |> assign(:lesson_chapter_id, nil)
      |> assign(:lesson_editing, nil)
      |> assign(:lesson_form, lesson_form(%{}))
      |> assign(:deleting_chapter, nil)
      |> assign(:deleting_lesson, nil)
      |> assign(:open_chapters, MapSet.new())

    {:ok, load_course(socket)}
  end

  # ── basic info ────────────────────────────────────────────────

  @impl true
  def handle_event("validate-basic", %{"course" => params}, socket) do
    {:noreply, assign(socket, :basic_form, course_form(params))}
  end

  def handle_event("save-basic", %{"course" => params}, socket) do
    teacher = socket.assigns.current_teacher
    changeset = course_changeset(params)

    if changeset.valid? do
      attrs = %{
        title: get_string(changeset, :title),
        subtitle: get_optional(changeset, :subtitle),
        description: get_optional(changeset, :description),
        cover_image_url: get_optional(changeset, :cover_image_url),
        level: get_atom(changeset, :level, :beginner),
        price_cents: get_price_cents(changeset),
        category_id: get_optional(changeset, :category_id)
      }

      case update_course(socket.assigns.course, attrs, teacher) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, "基本信息已保存") |> load_course()}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, assign(socket, :basic_form, Phoenix.Component.to_form(changeset, as: "course"))}
    end
  end

  def handle_event("transition", %{"to" => to}, socket) when to in ["publish", "archive"] do
    teacher = socket.assigns.current_teacher
    action = String.to_existing_atom(to)

    case socket.assigns.course
         |> Ash.Changeset.for_update(action, %{}, actor: teacher.actor, tenant: teacher.tenant)
         |> Ash.update() do
      {:ok, _} ->
        message = if to == "publish", do: "已发布", else: "已下架"
        {:noreply, socket |> put_flash(:info, message) |> load_course()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  # ── chapters ──────────────────────────────────────────────────

  def handle_event("toggle-chapter", %{"id" => id}, socket) do
    open =
      if MapSet.member?(socket.assigns.open_chapters, id) do
        MapSet.delete(socket.assigns.open_chapters, id)
      else
        MapSet.put(socket.assigns.open_chapters, id)
      end

    {:noreply, assign(socket, :open_chapters, open)}
  end

  def handle_event("open-create-chapter", _params, socket) do
    {:noreply,
     assign(socket, chapter_modal: true, chapter_editing: nil, chapter_form: chapter_form(%{}))}
  end

  def handle_event("open-edit-chapter", %{"id" => id}, socket) do
    case find_chapter(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "章节不存在")}

      chapter ->
        {:noreply,
         assign(socket,
           chapter_modal: true,
           chapter_editing: chapter,
           chapter_form: chapter_form(%{"title" => chapter.title})
         )}
    end
  end

  def handle_event("close-chapter-modal", _params, socket) do
    {:noreply, assign(socket, chapter_modal: nil, chapter_editing: nil)}
  end

  def handle_event("save-chapter", %{"chapter" => params}, socket) do
    teacher = socket.assigns.current_teacher
    changeset = chapter_changeset(params)

    if changeset.valid? do
      title = changeset |> Ecto.Changeset.get_field(:title) |> String.trim()

      result =
        if editing = socket.assigns.chapter_editing do
          editing
          |> Ash.Changeset.for_update(:update, %{title: title},
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.update()
        else
          max_order =
            socket.assigns.course.chapters
            |> Enum.map(&(&1.sort_order || 0))
            |> Enum.max(fn -> 0 end)

          Chapter
          |> Ash.Changeset.for_create(
            :create,
            %{title: title, course_id: socket.assigns.course_id, sort_order: max_order + 1},
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.create()
        end

      case result do
        {:ok, _} ->
          message = if socket.assigns.chapter_editing, do: "章节已更新", else: "章节已创建"

          {:noreply,
           socket
           |> assign(chapter_modal: nil, chapter_editing: nil)
           |> put_flash(:info, message)
           |> load_course()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply,
       assign(socket, :chapter_form, Phoenix.Component.to_form(changeset, as: "chapter"))}
    end
  end

  def handle_event("confirm-delete-chapter", %{"id" => id}, socket) do
    case find_chapter(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, "章节不存在")}
      chapter -> {:noreply, assign(socket, :deleting_chapter, chapter)}
    end
  end

  def handle_event("close-delete-chapter", _params, socket) do
    {:noreply, assign(socket, :deleting_chapter, nil)}
  end

  def handle_event("delete-chapter", _params, socket) do
    teacher = socket.assigns.current_teacher
    chapter = socket.assigns.deleting_chapter

    case Ash.destroy(chapter, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:deleting_chapter, nil)
         |> put_flash(:info, "已删除章节 #{chapter.title}（含其课时）")
         |> load_course()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  # ── lessons ───────────────────────────────────────────────────

  def handle_event("open-create-lesson", %{"chapter-id" => chapter_id}, socket) do
    {:noreply,
     assign(socket,
       lesson_modal: true,
       lesson_chapter_id: chapter_id,
       lesson_editing: nil,
       lesson_form: lesson_form(%{"content_type" => "video"})
     )}
  end

  def handle_event("open-edit-lesson", %{"id" => id}, socket) do
    case find_lesson(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "课时不存在")}

      {chapter_id, lesson} ->
        {:noreply,
         assign(socket,
           lesson_modal: true,
           lesson_chapter_id: chapter_id,
           lesson_editing: lesson,
           lesson_form:
             lesson_form(%{
               "title" => lesson.title,
               "content_type" => to_string(lesson.content_type || :video),
               "content_url" => lesson.content_url || "",
               "duration_seconds" => lesson.duration_seconds,
               "is_free_preview" => to_string(lesson.is_free_preview || false)
             })
         )}
    end
  end

  def handle_event("close-lesson-modal", _params, socket) do
    {:noreply, assign(socket, lesson_modal: nil, lesson_editing: nil, lesson_chapter_id: nil)}
  end

  def handle_event("save-lesson", %{"lesson" => params}, socket) do
    teacher = socket.assigns.current_teacher
    changeset = lesson_changeset(params)

    if changeset.valid? do
      get = &Ecto.Changeset.get_field(changeset, &1)

      attrs = %{
        title: get.(:title) |> to_string() |> String.trim(),
        content_type: get.(:content_type) |> to_string() |> String.to_existing_atom(),
        content_url: empty_to_nil(get.(:content_url)),
        duration_seconds: get.(:duration_seconds),
        is_free_preview: get.(:is_free_preview) == true
      }

      result =
        if editing = socket.assigns.lesson_editing do
          editing
          |> Ash.Changeset.for_update(:update, attrs,
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.update()
        else
          max_order =
            case find_chapter(socket, socket.assigns.lesson_chapter_id) do
              nil ->
                0

              chapter ->
                chapter.lessons |> Enum.map(&(&1.sort_order || 0)) |> Enum.max(fn -> 0 end)
            end

          Lesson
          |> Ash.Changeset.for_create(
            :create,
            Map.merge(attrs, %{
              chapter_id: socket.assigns.lesson_chapter_id,
              sort_order: max_order + 1
            }),
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.create()
        end

      case result do
        {:ok, _} ->
          message = if socket.assigns.lesson_editing, do: "课时已更新", else: "课时已创建"

          {:noreply,
           socket
           |> assign(lesson_modal: nil, lesson_editing: nil, lesson_chapter_id: nil)
           |> put_flash(:info, message)
           |> load_course()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :lesson_form, Phoenix.Component.to_form(changeset, as: "lesson"))}
    end
  end

  def handle_event("confirm-delete-lesson", %{"id" => id}, socket) do
    case find_lesson(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, "课时不存在")}
      {_chapter_id, lesson} -> {:noreply, assign(socket, :deleting_lesson, lesson)}
    end
  end

  def handle_event("close-delete-lesson", _params, socket) do
    {:noreply, assign(socket, :deleting_lesson, nil)}
  end

  def handle_event("delete-lesson", _params, socket) do
    teacher = socket.assigns.current_teacher
    lesson = socket.assigns.deleting_lesson

    case Ash.destroy(lesson, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:deleting_lesson, nil)
         |> put_flash(:info, "已删除课时 #{lesson.title}")
         |> load_course()}

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

  defp level_options, do: [{"初级", "beginner"}, {"中级", "intermediate"}, {"高级", "advanced"}]

  defp content_type_options, do: [{"视频", "video"}, {"文章", "article"}, {"PDF", "pdf"}]

  defp content_type_label(:video), do: "视频"
  defp content_type_label(:article), do: "文章"
  defp content_type_label(:pdf), do: "PDF"
  defp content_type_label(_), do: "-"

  defp sorted_lessons(nil), do: []
  defp sorted_lessons(lessons), do: Enum.sort_by(lessons, &(&1.sort_order || 0))

  defp can_publish?(nil), do: false

  defp can_publish?(course) do
    chapters = course.chapters || []
    chapters != [] and Enum.any?(chapters, &((&1.lessons || []) != []))
  end

  defp find_chapter(socket, id) do
    Enum.find((socket.assigns.course && socket.assigns.course.chapters) || [], &(&1.id == id))
  end

  defp find_lesson(socket, id) do
    chapters = (socket.assigns.course && socket.assigns.course.chapters) || []

    Enum.find_value(chapters, fn chapter ->
      case Enum.find(chapter.lessons || [], &(&1.id == id)) do
        nil -> nil
        lesson -> {chapter.id, lesson}
      end
    end)
  end

  defp list_categories(teacher) do
    case CourseCategory
         |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
         |> Ash.read() do
      {:ok, cats} -> Enum.sort_by(cats, & &1.name)
      _ -> []
    end
  end

  defp load_course(socket) do
    teacher = socket.assigns.current_teacher

    try do
      course =
        Course
        |> Ash.Query.filter(id == ^socket.assigns.course_id)
        |> Ash.Query.load(chapters: [:lessons])
        |> Ash.read_one!(actor: teacher.actor, tenant: teacher.tenant)

      chapters = course.chapters |> Enum.sort_by(&(&1.sort_order || 0))
      course = %{course | chapters: chapters}

      socket
      |> assign(:course, course)
      |> assign(:not_found, false)
      |> assign(:basic_form, course_form(course_to_params(course)))
      |> assign(:open_chapters, course.chapters |> Enum.map(& &1.id) |> MapSet.new())
    rescue
      _ -> assign(socket, course: nil, not_found: true)
    end
  end

  defp course_to_params(course) do
    %{
      "title" => course.title,
      "subtitle" => course.subtitle || "",
      "description" => course.description || "",
      "cover_image_url" => course.cover_image_url || "",
      "level" => to_string(course.level || :beginner),
      "price_yuan" => if(is_nil(course.price_cents), do: 0, else: course.price_cents / 100),
      "category_id" => course.category_id || ""
    }
  end

  defp course_form(params) do
    params |> course_changeset() |> Phoenix.Component.to_form(as: "course")
  end

  defp course_changeset(params) do
    types = %{
      title: :string,
      subtitle: :string,
      description: :string,
      cover_image_url: :string,
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

  defp chapter_form(params) do
    params
    |> chapter_changeset()
    |> Phoenix.Component.to_form(as: "chapter")
  end

  defp chapter_changeset(params) do
    {%{}, %{title: :string}}
    |> Ecto.Changeset.cast(params, [:title])
    |> Ecto.Changeset.validate_required([:title])
    |> Ecto.Changeset.validate_length(:title, max: 100)
  end

  defp lesson_form(params) do
    params
    |> lesson_changeset()
    |> Phoenix.Component.to_form(as: "lesson")
  end

  defp lesson_changeset(params) do
    types = %{
      title: :string,
      content_type: :string,
      content_url: :string,
      duration_seconds: :integer,
      is_free_preview: :boolean
    }

    {%{content_type: "video", is_free_preview: false}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:title, :content_type])
    |> Ecto.Changeset.validate_length(:title, max: 100)
    |> Ecto.Changeset.validate_inclusion(:content_type, @content_types)
    |> Ecto.Changeset.validate_number(:duration_seconds, greater_than_or_equal_to: 0)
  end

  defp update_course(course, attrs, teacher) do
    case course
         |> Ash.Changeset.for_update(:update, attrs, actor: teacher.actor, tenant: teacher.tenant)
         |> Ash.update() do
      {:ok, course} -> {:ok, course}
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  defp get_string(changeset, field) do
    changeset |> Ecto.Changeset.get_field(field) |> to_string() |> String.trim()
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

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)
  defp empty_to_nil(value), do: value

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
