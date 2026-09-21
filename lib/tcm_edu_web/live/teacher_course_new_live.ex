defmodule TcmEduWeb.TeacherCourseNewLive do
  @moduledoc """
  New course at `/teacher/courses/new`. Sectioned fieldset form; on
  success navigates back to the course list.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory
  alias TcmEduWeb.CourseCover

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @levels ~w(beginner intermediate advanced)

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    {:ok,
     socket
     |> assign(:page_title, "创建课程")
     |> assign(:page_subtitle, "先填基本信息，可顺手上传封面")
     |> assign(:categories, list_categories(teacher))
     |> assign(:form, course_form(%{}))
     |> CourseCover.allow_cover_upload()}
  end

  @impl true
  def handle_event("validate", %{"course" => params}, socket) do
    {:noreply, assign(socket, :form, course_form(params))}
  end

  def handle_event("cancel-cover", %{"ref" => ref}, socket) do
    {:noreply, Phoenix.LiveView.cancel_upload(socket, :cover, ref)}
  end

  def handle_event("save", %{"course" => params}, socket) do
    teacher = socket.assigns.current_teacher
    changeset = course_changeset(params)

    if changeset.valid? do
      attrs = %{
        title: get_string(changeset, :title),
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

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "course"))}
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

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "创建失败，请稍后重试"
  end
end
