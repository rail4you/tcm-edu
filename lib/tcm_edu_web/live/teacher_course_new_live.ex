defmodule TcmEduWeb.TeacherCourseNewLive do
  @moduledoc """
  New course at `/teacher/courses/new`. Sectioned fieldset form; on
  success navigates to the edit page for chapters and lessons.
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
     |> assign(:page_subtitle, "先填基本信息，创建后继续添加章节与课时")
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
      <.teacher_shell
        current_teacher={@current_teacher}
        current_page={:courses}
        page_title="创建课程"
        page_subtitle="先填基本信息，创建后继续添加章节与课时"
      >
        <:page_actions>
          <.link navigate="/teacher/courses" class="btn btn-soft btn-sm">返回列表</.link>
        </:page_actions>

        <.form
          for={@form}
          id="new-course-form"
          phx-change="validate"
          phx-submit="save"
          class="grid items-start gap-6 xl:grid-cols-3"
        >
          <div class="flex flex-col gap-6 xl:col-span-2">
            <fieldset class="fieldset rounded-box border border-base-300 bg-base-100 p-4 shadow-sm sm:p-6">
              <legend class="fieldset-legend px-2 text-sm font-medium">基本信息</legend>
              <.input
                field={@form[:title]}
                type="text"
                label="课程标题"
                placeholder="如：中医基础理论（上）"
                maxlength="100"
                required
              />
              <p class="label">一句话讲清这门课教什么，学生端列表页直接展示</p>
              <.input
                field={@form[:subtitle]}
                type="text"
                label="副标题"
                placeholder="一句话介绍（可选）"
                maxlength="200"
              />
              <.input
                field={@form[:description]}
                type="textarea"
                label="课程简介"
                placeholder="课程介绍、适合人群、学习目标（可选）"
                rows="5"
                maxlength="2000"
              />
              <.input
                field={@form[:cover_image_url]}
                type="text"
                label="封面图片 URL"
                placeholder="https://…（可选，也可以用 AI 配图生成）"
              />
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 bg-base-100 p-4 shadow-sm sm:p-6">
              <legend class="fieldset-legend px-2 text-sm font-medium">难度 · 价格 · 分类</legend>
              <div class="grid gap-2.5 sm:grid-cols-2">
                <.input field={@form[:level]} type="select" label="难度" options={level_options()} />
                <.input
                  field={@form[:category_id]}
                  type="select"
                  label="分类"
                  prompt="选择分类（可选）"
                  options={Enum.map(@categories, &{&1.name, &1.id})}
                />
              </div>
              <.input
                field={@form[:price_yuan]}
                type="number"
                label="价格（元）"
                min="0"
                step="0.01"
              />
              <p class="label">0 表示免费课程，学生可直接选课</p>
            </fieldset>
          </div>

          <aside class="flex flex-col gap-6 xl:sticky xl:top-6">
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body gap-2 p-4 sm:p-6">
                <p class="flex items-center gap-2 font-medium">
                  <.icon name="hero-light-bulb" class="size-5 text-warning" /> 备课小贴士
                </p>
                <ul class="flex list-disc flex-col gap-1 pl-5 text-sm text-base-content/80">
                  <li>标题控制在 20 字以内，突出课程主题</li>
                  <li>创建后先加章节再加课时，至少 1 章 1 节才能发布</li>
                  <li>没有封面？用左侧链接去 AI 配图生成一张</li>
                </ul>
                <.link navigate="/teacher/ai/image" class="btn btn-soft btn-sm mt-2 w-fit">
                  <.icon name="hero-photo" class="size-4" /> 去 AI 配图
                </.link>
              </div>
            </div>
            <div class="card bg-primary text-primary-content shadow-sm">
              <div class="card-body gap-2 p-4 sm:p-6">
                <p class="font-medium">准备好了吗？</p>
                <p class="text-sm opacity-80">创建后自动进入编辑页，继续添加章节与课时。</p>
                <.button type="submit" phx-disable-with="创建中..." class="btn border-0 bg-base-100">
                  创建并去添加章节
                </.button>
              </div>
            </div>
          </aside>
        </.form>
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
