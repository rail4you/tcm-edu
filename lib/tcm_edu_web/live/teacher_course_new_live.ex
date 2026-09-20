defmodule TcmEduWeb.TeacherCourseNewLive do
  @moduledoc """
  New course at `/teacher/courses/new`. On success navigates to the edit
  page so the teacher can add chapters and lessons right away.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @levels ~w(beginner intermediate advanced)

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    {:ok,
     socket
     |> assign(:page_title, "创建课程")
     |> assign(:categories, list_categories(teacher))
     |> assign(:form, course_form(%{}))}
  end

  @impl true
  def handle_event("validate", %{"course" => params}, socket) do
    {:noreply, assign(socket, :form, course_form(params))}
  end

  def handle_event("save", %{"course" => params}, socket) do
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
        teacher_id: teacher.id,
        category_id: get_optional(changeset, :category_id)
      }

      case Course.create_course(attrs, actor: teacher.actor, tenant: teacher.tenant) do
        {:ok, course} ->
          {:noreply,
           socket
           |> put_flash(:info, "课程已创建，继续添加章节与课时")
           |> push_navigate(to: "/teacher/courses/#{course.id}/edit")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "course"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell current_teacher={@current_teacher} current_page={:courses} page_title="创建课程">
        <div class="card max-w-3xl bg-base-100 shadow-sm">
          <div class="card-body gap-2.5 p-4 sm:p-6">
            <.form for={@form} id="new-course-form" phx-change="validate" phx-submit="save" class="flex flex-col gap-2.5">
              <.input field={@form[:title]} type="text" label="标题" placeholder="如：中医基础理论（上）" maxlength="100" required />
              <.input field={@form[:subtitle]} type="text" label="副标题" placeholder="一句话介绍（可选）" maxlength="200" />
              <.input field={@form[:description]} type="textarea" label="简介" placeholder="课程介绍、适合人群、学习目标（可选）" rows="4" maxlength="2000" />
              <.input field={@form[:cover_image_url]} type="text" label="封面图片 URL" placeholder="https://...（可选，可先留空）" />
              <.input field={@form[:level]} type="select" label="难度" options={level_options()} />
              <.input field={@form[:price_yuan]} type="number" label="价格（元，0 = 免费）" min="0" step="0.01" />
              <.input
                field={@form[:category_id]}
                type="select"
                label="分类"
                prompt="选择分类（可选）"
                options={Enum.map(@categories, &{&1.name, &1.id})}
              />
              <.button type="submit" class="btn-primary mt-2 w-fit">创建并去添加章节</.button>
            </.form>
          </div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
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
