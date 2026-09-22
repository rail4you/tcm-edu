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
           |> Ash.Changeset.for_update(:archive, %{},
             actor: teacher.actor,
             tenant: teacher.tenant
           )
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
end
