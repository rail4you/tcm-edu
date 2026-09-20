defmodule TcmEduWeb.StudentMistakesLive do
  @moduledoc """
  Mistake book at `/my-learning/mistakes`: the student's wrong attempts
  with stored AI explanations. "Ask AI" enqueues an explanation job and
  the list can be refreshed afterwards.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Quiz.Attempt
  alias TcmEdu.Workers.MistakeExplainerWorker

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "错题本")
     |> assign(:asking, nil)
     |> load_mistakes()}
  end

  @impl true
  def handle_event("ask-ai", %{"id" => attempt_id}, socket) do
    student = socket.assigns.current_student

    case MistakeExplainerWorker.new(%{
           "tenant" => student.tenant,
           "attempt_id" => attempt_id
         })
         |> Oban.insert() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:asking, attempt_id)
         |> put_flash(:info, "AI 解析已加入队列，稍后点「刷新」查看")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "提交失败：#{inspect(reason)}")}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> assign(:asking, nil) |> load_mistakes()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:mistakes}>
        <div class="mx-auto w-full max-w-4xl px-4 py-8 sm:px-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p class="text-2xl font-semibold md:text-3xl">错题本</p>
              <p class="mt-1 text-sm text-base-content/60">答错的题目都在这里，配 AI 解析</p>
            </div>
            <button class="btn btn-soft btn-sm" phx-click="refresh" phx-disable-with="刷新中...">
              <.icon name="hero-arrow-path" class="size-4" /> 刷新
            </button>
          </div>

          <div :if={@mistakes == []} class="mt-6 rounded-box bg-base-200/30 px-6 py-12 text-center">
            <.icon name="hero-check-circle" class="size-8 text-success" />
            <p class="mt-2 text-sm text-base-content/60">暂无错题，继续保持！</p>
            <.link navigate="/my-learning" class="btn btn-sm btn-primary mt-4">返回我的学习</.link>
          </div>

          <div :for={mistake <- @mistakes} class="card mt-4 bg-base-100 shadow-sm">
            <div class="card-body gap-2 p-4 sm:p-6">
              <div class="flex items-center gap-2">
                <span class="badge badge-soft badge-error">答错了</span>
                <p class="text-xs text-base-content/60">作答：{mistake.answer || "-"}</p>
              </div>
              <div :if={mistake.ai_explanation} class="rounded-box bg-base-200/30 p-3">
                <p class="flex items-center gap-1 text-xs font-medium">
                  <.icon name="hero-sparkles" class="size-4" /> AI 解析
                </p>
                <p class="mt-1 whitespace-pre-line text-sm text-base-content/80">{mistake.ai_explanation}</p>
              </div>
              <div class="card-actions justify-end">
                <button
                  :if={!mistake.ai_explanation}
                  class="btn btn-soft btn-sm"
                  phx-click="ask-ai"
                  phx-value-id={mistake.id}
                  phx-disable-with="提交中..."
                  disabled={@asking == mistake.id}
                >
                  <.icon name="hero-sparkles" class="size-4" />
                  {if @asking == mistake.id, do: "已提交，等待解析", else: "请 AI 解析"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  defp load_mistakes(socket) do
    student = socket.assigns.current_student

    mistakes =
      try do
        Attempt
        |> Ash.Query.for_read(:my_mistakes, %{},
          actor: student.actor,
          tenant: student.tenant
        )
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :mistakes, mistakes)
  end
end
