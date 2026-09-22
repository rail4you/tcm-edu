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
