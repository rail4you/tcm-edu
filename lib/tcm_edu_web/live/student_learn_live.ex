defmodule TcmEduWeb.StudentLearnLive do
  @moduledoc """
  Lesson viewer at `/learn` (requires login).

  Query params: `?course_id=<uuid>&lesson=<lesson_uuid>`. Shows the
  chapter outline, the active lesson content (video / article / pdf),
  prev/next navigation and a "mark complete" button that upserts progress.
  When every lesson is complete the enrollment is marked completed.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Courses.Course
  alias TcmEdu.Enrollment.Enrollment
  alias TcmEdu.Enrollment.Progress

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "学习")
     |> assign(:course_id, params["course_id"])
     |> assign(:lesson_id, params["lesson"])
     |> assign(:course, nil)
     |> assign(:enrollment, nil)
     |> assign(:progress_map, %{})
     |> assign(:not_found, false)
     |> load_all()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:course_id, params["course_id"])
     |> assign(:lesson_id, params["lesson"])
     |> load_all()}
  end

  @impl true
  def handle_event("complete-lesson", _params, socket) do
    student = socket.assigns.current_student
    enrollment = socket.assigns.enrollment
    lesson = active_lesson(socket.assigns)

    if enrollment && lesson do
      case upsert_progress(student, enrollment, lesson, 100, :completed) do
        :ok ->
          socket = load_all(socket)

          socket =
            if course_completed?(socket.assigns) do
              mark_enrollment_completed(student, enrollment)
              put_flash(socket, :info, "恭喜！本课程已学完")
            else
              put_flash(socket, :info, "本节已标记完成")
            end

          {:noreply, socket}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, socket}
    end
  end

  attr :lesson, :map, required: true

  defp lesson_body(%{lesson: %{content_type: :video, content_url: url}} = assigns)
       when is_binary(url) and url != "" do
    ~H"""
    <video src={@lesson.content_url} controls preload="metadata" class="aspect-video w-full rounded-box bg-black" />
    <p :if={@lesson.content_text} class="whitespace-pre-line text-sm text-base-content/80">{@lesson.content_text}</p>
    """
  end

  defp lesson_body(%{lesson: %{content_type: :article}} = assigns) do
    ~H"""
    <p class="whitespace-pre-line text-sm leading-7 text-base-content/80">
      {@lesson.content_text || "本节为文章课时，内容筹备中。"}
    </p>
    """
  end

  defp lesson_body(assigns) do
    ~H"""
    <p :if={@lesson.content_text} class="whitespace-pre-line text-sm text-base-content/80">{@lesson.content_text}</p>
    <.link
      :if={@lesson.content_url not in [nil, ""]}
      href={@lesson.content_url}
      target="_blank"
      rel="noopener"
      class="btn btn-soft btn-sm w-fit"
    >
      打开学习资料 <.icon name="hero-arrow-top-right-on-square" class="size-4" />
    </.link>
    <p :if={@lesson.content_url in [nil, ""] and !@lesson.content_text} class="text-sm text-base-content/60">
      本节内容筹备中。
    </p>
    """
  end

  defp learn_path(course_id, lesson_id), do: "/learn?course_id=#{course_id}&lesson=#{lesson_id}"

  defp flat_lessons(nil), do: []

  defp flat_lessons(course) do
    (course.chapters || [])
    |> Enum.sort_by(&(&1.sort_order || 0))
    |> Enum.flat_map(&Enum.sort_by(&1.lessons || [], fn l -> l.sort_order || 0 end))
  end

  defp active_lesson(%{course: nil}), do: nil

  defp active_lesson(%{course: _course, lesson_id: nil} = assigns),
    do: List.first(flat_lessons(assigns.course))

  defp active_lesson(%{course: course, lesson_id: lesson_id}) do
    Enum.find(flat_lessons(course), &(&1.id == lesson_id))
  end

  defp active_lesson_assign(lesson_id, flat) do
    if is_nil(lesson_id), do: List.first(flat), else: Enum.find(flat, &(&1.id == lesson_id))
  end

  defp prev_lesson(lesson_id, flat) do
    index = Enum.find_index(flat, &(&1.id == lesson_id)) || 0
    if index > 0, do: Enum.at(flat, index - 1), else: nil
  end

  defp next_lesson(lesson_id, flat) do
    index = Enum.find_index(flat, &(&1.id == lesson_id)) || -1
    Enum.at(flat, index + 1)
  end

  defp lesson_done?(progress_map, lesson_id) do
    case Map.get(progress_map, lesson_id) do
      %{progress_pct: 100} -> true
      %{status: :completed} -> true
      _ -> false
    end
  end

  defp overall_pct(_progress_map, []), do: 0

  defp overall_pct(progress_map, flat) do
    pcts = Enum.map(flat, &(Map.get(progress_map, &1.id, %{}) |> Map.get(:progress_pct, 0)))
    round(Enum.sum(pcts) / length(pcts))
  end

  defp course_completed?(%{course: nil}), do: false

  defp course_completed?(%{course: course, progress_map: progress_map}) do
    flat = flat_lessons(course)
    flat != [] and Enum.all?(flat, &lesson_done?(progress_map, &1.id))
  end

  defp load_all(%{assigns: %{course_id: nil}} = socket) do
    assign(socket,
      course: nil,
      enrollment: nil,
      not_found: true,
      flat_lessons: [],
      progress_map: %{}
    )
  end

  defp load_all(socket) do
    student = socket.assigns.current_student

    try do
      course =
        Course
        |> Ash.Query.filter(id == ^socket.assigns.course_id)
        |> Ash.Query.load(chapters: [:lessons])
        |> Ash.read_one!(actor: student.actor, tenant: student.tenant)

      chapters = course.chapters |> Enum.sort_by(&(&1.sort_order || 0))
      course = %{course | chapters: chapters}
      enrollment = find_enrollment(student, course.id)
      progress_map = load_progress(student, enrollment)

      flat = flat_lessons(course)
      lesson_id = socket.assigns.lesson_id || flat |> List.first(%{}) |> Map.get(:id)

      socket
      |> assign(:course, course)
      |> assign(:enrollment, enrollment)
      |> assign(:progress_map, progress_map)
      |> assign(:flat_lessons, flat)
      |> assign(:lesson_id, lesson_id)
      |> assign(:not_found, false)
    rescue
      _ ->
        assign(socket,
          course: nil,
          enrollment: nil,
          not_found: true,
          flat_lessons: [],
          progress_map: %{}
        )
    end
  end

  defp find_enrollment(student, course_id) do
    Enrollment
    |> Ash.Query.filter(user_id == ^student.id and course_id == ^course_id and status == :active)
    |> Ash.read_one(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, enrollment} -> enrollment
      _ -> nil
    end
  end

  defp load_progress(_student, nil), do: %{}

  defp load_progress(student, enrollment) do
    Progress
    |> Ash.Query.filter(enrollment_id == ^enrollment.id)
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, records} -> Map.new(records, &{&1.lesson_id, &1})
      _ -> %{}
    end
  end

  defp upsert_progress(student, enrollment, lesson, pct, status) do
    attrs = %{
      enrollment_id: enrollment.id,
      lesson_id: lesson.id,
      progress_pct: pct,
      status: status
    }

    case Progress
         |> Ash.Changeset.for_create(:upsert_progress, attrs,
           actor: student.actor,
           tenant: student.tenant
         )
         |> Ash.create() do
      {:ok, _} -> :ok
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  defp mark_enrollment_completed(student, enrollment) do
    enrollment
    |> Ash.Changeset.for_update(:mark_completed, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.update()
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "保存失败，请稍后重试"
  end
end
