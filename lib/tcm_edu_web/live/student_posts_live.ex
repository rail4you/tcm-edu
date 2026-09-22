defmodule TcmEduWeb.StudentPostsLive do
  @moduledoc """
  Community posts at `/posts` (requires login, mirroring the React page).
  Expandable post bodies; creation lives at `/posts/new`.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Post

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "交流")
     |> assign(:error, nil)
     |> load_posts()}
  end

  defp load_posts(socket) do
    student = socket.assigns.current_student

    try do
      posts =
        Post
        |> Ash.Query.for_read(:read, %{}, actor: student.actor, tenant: student.tenant)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!()

      assign(socket, posts: posts, error: nil)
    rescue
      e ->
        assign(socket, posts: [], error: "加载失败：#{ash_message(e)}")
    end
  end

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "请稍后重试"
  end
end
