defmodule TcmEduWeb.TeacherCourseNewLive do
  @moduledoc """
  New course at `/teacher/courses/new`. Sectioned fieldset form; on
  success navigates back to the course list.

  Form is built from the Ash resource via `AshPhoenix.Form.for_create/3`,
  so field types / validations / accept list come from the
  `:create_course` action in `TcmEdu.Courses.Course` (no hand-rolled
  Ecto changesets). `teacher_id` is injected server-side via
  `prepare_source` so it never reaches the client.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory
  alias TcmEduWeb.CourseCover

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    {:ok,
     socket
     |> assign(:page_title, "创建课程")
     |> assign(:page_subtitle, "先填基本信息，可顺手上传封面")
     |> assign(:categories, list_categories(teacher))
     |> assign(:form, course_form(teacher, %{}))
     |> CourseCover.allow_cover_upload()}
  end

  @impl true
  def handle_event("validate", %{"course" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("cancel-cover", %{"ref" => ref}, socket) do
    {:noreply, Phoenix.LiveView.cancel_upload(socket, :cover, ref)}
  end

  def handle_event("save", %{"course" => params}, socket) do
    teacher = socket.assigns.current_teacher

    # 提前校验一次,使 form 上的 errors 字段反映本次输入(否则只在 submit 失败后才更新)。
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, course} ->
        socket =
          case CourseCover.consume_cover(socket, course, teacher) do
            {:ok, _url} ->
              put_flash(socket, :info, "课程已创建，封面已上传")

            {:error, message} ->
              put_flash(
                socket,
                :info,
                "课程已创建，但封面上传失败（#{message}），可在课程列表编辑中重试"
              )

            :no_entry ->
              put_flash(socket, :info, "课程已创建")
          end

        {:noreply, push_navigate(socket, to: "/teacher/courses")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
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

  # 基于 Ash 资源 action 构建表单:字段类型、accept 列表、约束都来自
  # `:create_course` action;`teacher_id` 走 `prepare_source` 由服务端注入,
  # 避免表单回显时被改写。表单字段直接绑定 `:price_cents`(数据库存的就是分),
  # 沿用 `allow_nil? false` / 约束由资源提供,无需手写 Ecto changeset。
  defp course_form(teacher, params) do
    Course
    |> AshPhoenix.Form.for_create(:create_course,
      actor: teacher.actor,
      tenant: teacher.tenant,
      as: "course",
      params: params,
      prepare_source: fn changeset ->
        Ash.Changeset.force_change_attribute(changeset, :teacher_id, teacher.id)
      end
    )
    |> to_form()
  end
end
