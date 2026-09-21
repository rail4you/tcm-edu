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
