defmodule TcmEduWeb.TeacherAILessonLive do
  @moduledoc """
  AI lesson planning at `/teacher/ai/lesson-plan`.

  The teacher describes a topic; generation runs in a background Task
  and streams back into the page. The finished plan can be saved as a
  draft course in one click.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.AI.LessonPlan
  alias TcmEdu.Courses.Course

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI 备课")
     |> assign(:page_subtitle, "输入主题，AI 生成结构化教案，可一键存为课程草稿")
     |> assign(:form, plan_form(%{}))
     |> assign(:generating, false)
     |> assign(:plan, nil)
     |> assign(:plan_topic, nil)
     |> assign(:run_ref, nil)}
  end

  @impl true
  def handle_event("validate", %{"plan" => params}, socket) do
    {:noreply, assign(socket, :form, plan_form(params))}
  end

  def handle_event("generate", %{"plan" => params}, socket) do
    changeset = plan_changeset(params)

    if changeset.valid? and not socket.assigns.generating do
      lv = self()
      ref = make_ref()
      topic = get_field(changeset, :topic) |> String.trim()

      opts = [
        topic: topic,
        subject: get_field(changeset, :subject) |> empty_to_nil() || "中医",
        level: get_field(changeset, :level) |> to_string(),
        audience: get_field(changeset, :audience) |> empty_to_nil()
      ]

      Task.start(fn ->
        result = LessonPlan.generate(opts)
        if Process.alive?(lv), do: send(lv, {:plan_done, ref, result})
      end)

      {:noreply,
       socket
       |> assign(:generating, true)
       |> assign(:plan, nil)
       |> assign(:plan_topic, topic)
       |> assign(:run_ref, ref)}
    else
      {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "plan"))}
    end
  end

  def handle_event("save-draft", _params, socket) do
    teacher = socket.assigns.current_teacher
    topic = socket.assigns.plan_topic || "AI 教案"

    attrs = %{
      title: String.slice(topic, 0, 100),
      subtitle: "AI 备课生成",
      description: socket.assigns.plan,
      level: :beginner,
      price_cents: 0,
      teacher_id: teacher.id
    }

    case Course.create_course(attrs, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, "已存为课程草稿，继续添加章节与课时")
         |> push_navigate(to: "/teacher/courses/#{course.id}/edit")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  @impl true
  def handle_info({:plan_done, ref, result}, socket) do
    if ref == socket.assigns.run_ref do
      case result do
        {:ok, plan} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> assign(:plan, plan)
           |> assign(:run_ref, nil)
           |> put_flash(:info, "教案已生成")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> assign(:run_ref, nil)
           |> put_flash(:error, "生成失败：#{format_reason(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell
        current_teacher={@current_teacher}
        current_page={:ai_lesson}
        page_title="AI 备课"
        page_subtitle="输入主题，AI 生成结构化教案，可一键存为课程草稿"
      >
        <div class="grid items-start gap-6 xl:grid-cols-5">
          <fieldset class="fieldset rounded-box border border-base-300 bg-base-100 p-4 shadow-sm sm:p-6 xl:col-span-2">
            <legend class="fieldset-legend px-2 text-sm font-medium">备课需求</legend>
            <.form
              for={@form}
              id="ai-lesson-form"
              phx-change="validate"
              phx-submit="generate"
              class="flex flex-col gap-2.5"
            >
              <.input field={@form[:topic]} type="text" label="主题" placeholder="如：手太阴肺经腧穴" maxlength="100" required />
              <.input field={@form[:subject]} type="text" label="学科" placeholder="如：中医基础（可选）" maxlength="50" />
              <.input field={@form[:level]} type="select" label="学段" options={level_options()} />
              <.input field={@form[:audience]} type="text" label="授课对象" placeholder="如：大二本科生（可选）" maxlength="100" />
              <.button
                type="submit"
                phx-disable-with="生成中..."
                class="btn-primary mt-2 w-full"
                disabled={@generating}
              >
                <.icon name="hero-sparkles" class="size-4" /> 生成教案
              </.button>
            </.form>
            <p class="label">生成约需十几秒，请耐心等待；需要配置大模型 Key 才能使用</p>
          </fieldset>

          <div class="card bg-base-100 shadow-sm xl:col-span-3">
            <div class="card-body gap-2 p-4 sm:p-6">
              <div class="flex items-center justify-between gap-2">
                <p class="font-medium">生成结果</p>
                <button
                  :if={@plan}
                  class="btn btn-primary btn-sm"
                  phx-click="save-draft"
                  phx-disable-with="保存中..."
                >
                  <.icon name="hero-plus" class="size-4" /> 存为课程草稿
                </button>
              </div>
              <div :if={@generating} class="flex flex-col gap-2 py-6">
                <div class="skeleton h-4 w-3/4" />
                <div class="skeleton h-4 w-full" />
                <div class="skeleton h-4 w-5/6" />
                <div class="skeleton h-4 w-2/3" />
                <p class="mt-2 flex items-center gap-2 text-sm text-base-content/60">
                  <span class="loading loading-dots loading-sm" /> AI 正在撰写教案…
                </p>
              </div>
              <p :if={!@generating and !@plan} class="py-6 text-center text-sm text-base-content/60">
                在左侧填写主题后点击生成
              </p>
              <article :if={@plan} class="max-w-none text-sm">
                <p class="whitespace-pre-line leading-7">{@plan}</p>
              </article>
            </div>
          </div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
  end

  defp level_options, do: [{"本科", "本科"}, {"规培", "规培"}, {"继续教育", "继续教育"}]

  defp plan_form(params) do
    params |> plan_changeset() |> Phoenix.Component.to_form(as: "plan")
  end

  defp plan_changeset(params) do
    types = %{topic: :string, subject: :string, level: :string, audience: :string}

    {%{level: "本科"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:topic])
    |> Ecto.Changeset.validate_length(:topic, max: 100)
  end

  defp get_field(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp format_reason(:missing_key), do: "未配置大模型 Key"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "保存失败，请稍后重试"
  end
end
