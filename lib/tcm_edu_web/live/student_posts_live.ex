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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:posts}>
        <div class="mx-auto w-full max-w-4xl px-4 py-8 sm:px-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p class="text-2xl font-semibold md:text-3xl">学习交流</p>
              <p class="mt-1 text-sm text-base-content/60">分享学习心得，互相答疑</p>
            </div>
            <.link navigate="/posts/new" class="btn btn-primary btn-sm" id="new-post-btn">
              <.icon name="hero-plus" class="size-4" /> 发帖
            </.link>
          </div>

          <div :if={@error} class="alert alert-soft alert-error mt-4">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <p class="text-sm">{@error}</p>
          </div>

          <div :for={post <- @posts} class="card mt-4 bg-base-100 shadow-sm">
            <div class="card-body gap-2 p-4 sm:p-6">
              <p class="font-medium">{post.title}</p>
              <p class="text-xs text-base-content/60">{format_time(post.inserted_at)}</p>
              <details class="text-sm">
                <summary class="cursor-pointer text-primary">展开正文</summary>
                <p class="mt-2 whitespace-pre-line text-base-content/80">{post.body || "（无正文）"}</p>
              </details>
            </div>
          </div>

          <div :if={!@error and @posts == []} class="mt-4 rounded-box bg-base-200/30 px-6 py-12 text-center">
            <.icon name="hero-chat-bubble-left-right" class="size-8 text-base-content/40" />
            <p class="mt-2 text-sm text-base-content/60">还没有帖子，来发第一帖吧</p>
            <.link navigate="/posts/new" class="btn btn-sm btn-primary mt-4">发帖</.link>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
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
