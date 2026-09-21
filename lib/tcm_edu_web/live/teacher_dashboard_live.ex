defmodule TcmEduWeb.TeacherDashboardLive do
  @moduledoc """
  Teacher home at `/teacher`: course status stats, recent courses and
  quick actions in an asymmetrical grid.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory

  @levels ~w(beginner intermediate advanced)

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher
    courses = list_my_courses(teacher)

    stats = %{
      total: length(courses),
      draft: Enum.count(courses, &(&1.status == :draft)),
      published: Enum.count(courses, &(&1.status == :published)),
      archived: Enum.count(courses, &(&1.status == :archived))
    }

    {:ok,
     socket
     |> assign(:page_title, "工作台")
     |> assign(:page_subtitle, greeting(teacher))
     |> assign(:stats, stats)
     |> assign(:recent, Enum.take(courses, 5))
     |> assign(:categories, list_categories(teacher))
     |> assign(:create_modal, false)
     |> assign(:create_form, course_form(%{}))}
  end

  @impl true
  def handle_event("open-create", _params, socket) do
    {:noreply, assign(socket, :create_modal, true) |> assign(:create_form, course_form(%{}))}
  end

  def handle_event("close-create", _params, socket) do
    {:noreply, assign(socket, :create_modal, false)}
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
           |> assign(:create_modal, false)
           |> put_flash(:info, "课程《#{course.title}》已创建，回到列表继续编辑")
           |> push_navigate(to: "/teacher/courses")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :create_form, Phoenix.Component.to_form(changeset, as: "course"))}
    end
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, default: "hero-chart-bar"
  attr :tone, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body gap-2 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">{@title}</p>
          <span class="flex size-10 items-center justify-center rounded-box bg-primary/10 text-primary">
            <.icon name={@icon} class="size-5" />
          </span>
        </div>
        <p class={["text-3xl font-semibold tabular-nums", @tone]}>{@value}</p>
        <p :if={@hint} class="text-xs text-base-content/60">{@hint}</p>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={@status == :draft} class="badge badge-soft badge-xs badge-ghost">草稿</span>
    <span :if={@status == :published} class="badge badge-soft badge-xs badge-success">已发布</span>
    <span :if={@status == :archived} class="badge badge-soft badge-xs badge-warning">已下架</span>
    """
  end

  defp greeting(%{name: name}), do: "#{name}，今天也要带好每一位学生"

  defp list_my_courses(teacher) do
    Course
    |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.Query.load([:lesson_count])
    |> Ash.read!()
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  rescue
    _ -> []
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
