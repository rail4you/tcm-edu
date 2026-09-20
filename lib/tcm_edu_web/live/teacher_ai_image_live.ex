defmodule TcmEduWeb.TeacherAIImageLive do
  @moduledoc """
  AI medical illustration at `/teacher/ai/image`.

  Prompt + style/size form; generation (task creation + polling + OSS
  archiving) runs in a background Task and the resulting images render
  in a gallery. URLs can be copied into a course cover.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.AI.MedicalImage

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI 配图")
     |> assign(:page_subtitle, "生成经络腧穴、中药、示意图等教学配图，自动归档")
     |> assign(:form, image_form(%{}))
     |> assign(:generating, false)
     |> assign(:urls, [])
     |> assign(:run_ref, nil)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell
        current_teacher={@current_teacher}
        current_page={:ai_image}
        page_title="AI 配图"
        page_subtitle="生成经络腧穴、中药、示意图等教学配图，自动归档"
      >
        <div class="grid items-start gap-6 xl:grid-cols-5">
          <fieldset class="fieldset rounded-box border border-base-300 bg-base-100 p-4 shadow-sm sm:p-6 xl:col-span-2">
            <legend class="fieldset-legend px-2 text-sm font-medium">作画需求</legend>
            <.form
              for={@form}
              id="ai-image-form"
              phx-change="validate"
              phx-submit="generate"
              class="flex flex-col gap-2.5"
            >
              <.input
                field={@form[:prompt]}
                type="textarea"
                label="画面描述"
                placeholder="如：手太阴肺经循行示意图，标注主要腧穴，水墨风格"
                rows="4"
                maxlength="500"
                required
              />
              <div class="grid gap-2.5 sm:grid-cols-2">
                <.input field={@form[:style]} type="select" label="风格" options={style_options()} />
                <.input field={@form[:size]} type="select" label="尺寸" options={size_options()} />
              </div>
              <.button
                type="submit"
                phx-disable-with="生成中..."
                class="btn-primary mt-2 w-full"
                disabled={@generating}
              >
                <.icon name="hero-photo" class="size-4" /> 生成配图
              </.button>
            </.form>
            <p class="label">图片生成 + 归档约需半分钟；需要配置图片模型 Key 才能使用</p>
          </fieldset>

          <div class="card bg-base-100 shadow-sm xl:col-span-3">
            <div class="card-body gap-2 p-4 sm:p-6">
              <p class="font-medium">生成结果</p>
              <div :if={@generating} class="flex flex-col items-center gap-2 py-10">
                <span class="loading loading-spinner loading-lg text-primary" />
                <p class="text-sm text-base-content/60">正在作画并归档，请稍候…</p>
              </div>
              <p :if={!@generating and @urls == []} class="py-6 text-center text-sm text-base-content/60">
                在左侧描述画面后点击生成
              </p>
              <div :if={@urls != []} class="grid gap-4 sm:grid-cols-2">
                <div :for={url <- @urls} class="flex flex-col gap-2">
                  <img src={url} alt="AI 生成的教学配图" loading="lazy" class="aspect-square w-full rounded-box object-cover" />
                  <div class="flex items-center gap-2">
                    <input type="text" readonly value={url} class="input input-bordered input-xs w-full" aria-label="图片链接" />
                  </div>
                  <p class="text-xs text-base-content/60">已归档，可将链接粘贴为课程封面</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
  end

  defp style_options,
    do: [{"写实", "realistic"}, {"水墨", "ink"}, {"扁平插画", "flat"}, {"解剖图", "anatomy"}]

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
