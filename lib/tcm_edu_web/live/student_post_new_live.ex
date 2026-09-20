defmodule TcmEduWeb.StudentPostNewLive do
  @moduledoc """
  New post at `/posts/new`. On success returns to the post list.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  alias TcmEdu.Post

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "发帖")
     |> assign(:form, post_form(%{}))}
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    {:noreply, assign(socket, :form, post_form(params))}
  end

  def handle_event("save", %{"post" => params}, socket) do
    student = socket.assigns.current_student
    changeset = post_changeset(params)

    if changeset.valid? do
      attrs = %{
        title: changeset |> Ecto.Changeset.get_field(:title) |> String.trim(),
        body: changeset |> Ecto.Changeset.get_field(:body) |> empty_to_nil()
      }

      case Post
           |> Ash.Changeset.for_create(:create, attrs,
             actor: student.actor,
             tenant: student.tenant
           )
           |> Ash.create() do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "发布成功")
           |> push_navigate(to: "/posts")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "post"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:post_new}>
        <div class="mx-auto w-full max-w-2xl px-4 py-8 sm:px-6">
          <p class="text-2xl font-semibold md:text-3xl">发帖</p>
          <p class="mt-1 text-sm text-base-content/60">分享你的学习心得或提出问题</p>
          <div class="card mt-4 bg-base-100 shadow-sm">
            <div class="card-body gap-2.5 p-4 sm:p-6">
              <.form for={@form} id="new-post-form" phx-change="validate" phx-submit="save" class="flex flex-col gap-2.5">
                <.input field={@form[:title]} type="text" label="标题" placeholder="一句话概括" maxlength="200" required />
                <.input field={@form[:body]} type="textarea" label="正文" placeholder="详细说说（可选，最多 10000 字）" rows="8" maxlength="10000" />
                <div class="flex gap-2">
                  <.link navigate="/posts" class="btn btn-soft">取消</.link>
                  <.button type="submit" phx-disable-with="发布中..." class="btn-primary">发布</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  defp post_form(params) do
    params |> post_changeset() |> Phoenix.Component.to_form(as: "post")
  end

  defp post_changeset(params) do
    {%{}, %{title: :string, body: :string}}
    |> Ecto.Changeset.cast(params, [:title, :body])
    |> Ecto.Changeset.validate_required([:title])
    |> Ecto.Changeset.validate_length(:title, min: 1, max: 200)
    |> Ecto.Changeset.validate_length(:body, max: 10_000)
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "发布失败，请稍后重试"
  end
end
