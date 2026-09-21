defmodule TcmEduWeb.TeacherAIImageLive do
  @moduledoc """
  AI medical illustration at `/teacher/ai/image`.

  Prompt + style/size form; generation (task creation + polling + OSS
  archiving) runs in a background Task and the resulting images render
  in a gallery. Each image can be set as a course cover directly
  (downloaded and attached via AshStorage).
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.AI.MedicalImage
  alias TcmEdu.Courses.Course
  alias TcmEduWeb.CourseCover

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    {:ok,
     socket
     |> assign(:page_title, "AI 配图")
     |> assign(:page_subtitle, "生成经络腧穴、中药、示意图等教学配图，自动归档")
     |> assign(:form, image_form(%{}))
     |> assign(:generating, false)
     |> assign(:urls, [])
     |> assign(:run_ref, nil)
     |> assign(:courses, list_courses(teacher))
     |> assign(:cover_course_id, nil)}
  end

  @impl true
  def handle_event("validate", %{"image" => params}, socket) do
    {:noreply, assign(socket, :form, image_form(params))}
  end

  def handle_event("generate", %{"image" => params}, socket) do
    changeset = image_changeset(params)

    if changeset.valid? and not socket.assigns.generating do
      lv = self()
      ref = make_ref()
      get = &Ecto.Changeset.get_field(changeset, &1)

      opts =
        [
          key_prefix: "ai/teacher",
          style: empty_to_nil(get.(:style)),
          size: empty_to_nil(get.(:size))
        ]
        |> Enum.reject(fn {_, v} -> is_nil(v) end)

      prompt = get.(:prompt) |> to_string() |> String.trim()

      Task.start(fn ->
        result = MedicalImage.generate_and_store(prompt, opts)
        if Process.alive?(lv), do: send(lv, {:image_done, ref, result})
      end)

      {:noreply,
       socket |> assign(:generating, true) |> assign(:urls, []) |> assign(:run_ref, ref)}
    else
      {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "image"))}
    end
  end

  def handle_event("select-cover-course", %{"cover" => %{"course_id" => course_id}}, socket) do
    {:noreply, assign(socket, :cover_course_id, empty_to_nil(course_id))}
  end

  def handle_event("set-cover", %{"url" => url}, socket) do
    teacher = socket.assigns.current_teacher

    with course_id when not is_nil(course_id) <- socket.assigns.cover_course_id,
         {:ok, course} <- fetch_course(course_id, teacher),
         :ok <- CourseCover.attach_from_url(course, teacher, url, basename(url)) do
      {:noreply, put_flash(socket, :info, "已设为《#{course.title}》的封面")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "请先选择一门课程")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "课程不存在或无权限")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, "设为封面失败：#{message}")}
    end
  end

  @impl true
  def handle_info({:image_done, ref, result}, socket) do
    if ref == socket.assigns.run_ref do
      case result do
        {:ok, urls} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> assign(:urls, urls)
           |> assign(:run_ref, nil)
           |> put_flash(:info, "配图已生成并归档")}

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

  defp style_options,
    do: [{"写实", "realistic"}, {"水墨", "ink"}, {"扁平插画", "flat"}, {"解剖图", "anatomy"}]

  defp list_courses(teacher) do
    case Course
         |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id},
           actor: teacher.actor,
           tenant: teacher.tenant
         )
         |> Ash.read() do
      {:ok, courses} -> Enum.sort_by(courses, & &1.title)
      _ -> []
    end
  end

  defp fetch_course(course_id, teacher) do
    case Ash.get(Course, course_id, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, course} when not is_nil(course) -> {:ok, course}
      _ -> {:error, :not_found}
    end
  end

  defp basename(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) ->
        path |> Path.basename() |> then(fn b -> if b == "", do: "ai-cover.png", else: b end)

      _ ->
        "ai-cover.png"
    end
  end

  defp size_options, do: [{"方形 1024", "1024x1024"}, {"横版 16:9", "16:9"}, {"竖版 9:16", "9:16"}]

  defp image_form(params) do
    params |> image_changeset() |> Phoenix.Component.to_form(as: "image")
  end

  defp image_changeset(params) do
    types = %{prompt: :string, style: :string, size: :string}

    {%{style: "realistic", size: "1024x1024"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:prompt])
    |> Ecto.Changeset.validate_length(:prompt, max: 500)
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp format_reason(:missing_key), do: "未配置图片模型 Key"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
