defmodule TcmEduWeb.TeacherMdtLive do
  @moduledoc """
  教师端「MDT 会诊」页 at `/teacher/mdt`。

  从 mock 模板一键创建并发布 MCU 病例，供学生在 `/mdt` 选择进入会诊。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query
  alias TcmEdu.Mdt.{Case, Room}
  alias TcmEdu.Mdt.Examples, as: MdtExamples

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    socket =
      socket
      |> assign(:page_title, "MDT 会诊")
      |> assign(:cases, list_cases(teacher))
      |> assign(:rooms, list_rooms(teacher))

    {:ok, socket}
  end

  @impl true
  def handle_event("create-from-template", %{"key" => key}, socket) do
    teacher = socket.assigns.current_teacher

    case MdtExamples.create!(key, teacher, tenant: teacher.tenant) do
      {:ok, _case} ->
        {:noreply,
         socket
         |> load_cases()
         |> put_flash(:info, "已从模板创建并发布 MDT 病例")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "创建失败：#{reason}")}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    with %Case{} = case <- Enum.find(socket.assigns.cases, &(&1.id == id)),
         {:ok, _} <-
           case
           |> Ash.Changeset.for_update(:archive, %{}, actor: teacher.actor, tenant: teacher.tenant)
           |> Ash.update() do
      {:noreply, socket |> load_cases() |> put_flash(:info, "已归档")}
    else
      _ -> {:noreply, put_flash(socket, :error, "操作失败")}
    end
  end

  # ── helpers ───────────────────────────────────────────────

  defp list_cases(teacher) do
    Case
    |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: teacher.actor, tenant: teacher.tenant)
    |> case do
      {:ok, cases} -> cases
      _ -> []
    end
  rescue
    _ -> []
  end

  defp list_rooms(teacher) do
    Room
    |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(20)
    |> Ash.read(actor: teacher.actor, tenant: teacher.tenant)
    |> case do
      {:ok, rooms} -> rooms
      _ -> []
    end
  rescue
    _ -> []
  end

  defp load_cases(socket) do
    assign(socket, :cases, list_cases(socket.assigns.current_teacher))
  end

  defp rooms_label(%Room{} = room) do
    "#{room.case_snapshot["name"] || "会诊"} · #{status_text(room.status)} · #{room.message_count} 条"
  end

  defp status_text(:open), do: "进行中"
  defp status_text(:concluded), do: "已汇总"
  defp status_text(:abandoned), do: "已结束"
  defp status_text(_), do: "—"

  # ── render ────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell current_teacher={@current_teacher} current_page={:mdt}>
        <div class="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h1 class="text-xl font-semibold">MDT 会诊</h1>
              <p class="mt-1 text-sm text-base-content/60">
                从模板创建多学科会诊病例，学生进入后由 AI 扮演患者与未认领科室专家。
              </p>
            </div>
            <details class="dropdown dropdown-end">
              <summary class="btn btn-primary btn-sm">从模板创建病例</summary>
              <ul class="menu dropdown-content z-10 mt-2 w-72 rounded-box border border-base-300 bg-base-100 p-2 shadow-md">
                <li :for={t <- MdtExamples.list()}>
                  <button type="button" phx-click="create-from-template" phx-value-key={t.key} class="text-left">
                    {t.label}
                  </button>
                </li>
              </ul>
            </details>
          </div>

          <div class="mt-4 grid items-start gap-4 lg:grid-cols-2">
            <div class="card border border-base-300 bg-base-100">
              <div class="card-body gap-2 p-4">
                <p class="font-medium">病例</p>
                <div
                  :for={case <- @cases}
                  class="flex items-center justify-between gap-2 rounded-box border border-base-300 p-3"
                >
                  <div>
                    <p class="text-sm font-medium">{case.name}</p>
                    <p class="text-xs text-base-content/60">{case.complaint}</p>
                    <div class="mt-1 flex flex-wrap gap-1">
                      <span :for={d <- case.departments || []} class="badge badge-ghost badge-sm">{d}</span>
                    </div>
                  </div>
                  <div class="flex flex-col items-end gap-1">
                    <span class="badge badge-soft badge-sm">
                      {status_text(case.status)}
                    </span>
                    <button
                      :if={case.status == :published}
                      type="button"
                      phx-click="archive"
                      phx-value-id={case.id}
                      class="btn btn-ghost btn-xs text-error"
                    >
                      归档
                    </button>
                  </div>
                </div>
                <p :if={@cases == []} class="py-4 text-center text-sm text-base-content/60">暂无病例</p>
              </div>
            </div>

            <div class="card border border-base-300 bg-base-100">
              <div class="card-body gap-2 p-4">
                <p class="font-medium">会诊记录</p>
                <p :for={room <- @rooms} class="rounded-box border border-base-300 p-3 text-sm">
                  {rooms_label(room)}
                </p>
                <p :if={@rooms == []} class="py-4 text-center text-sm text-base-content/60">暂无会诊</p>
              </div>
            </div>
          </div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
  end
end