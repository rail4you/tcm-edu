defmodule TcmEduWeb.StudentMdtLive do
  @moduledoc """
  学生端「多学科会诊（MDT）」列表页 at `/mdt`.

  展示已发布可参与的会诊病例，学生选择某个病例进入会诊室（未认领的科室由
  AI 扮演专家补充）。同时列出自己已参加的会诊室。

  ## 体验

    1. 从病例列表点「进入会诊」→ 以第一个科室角色创建会诊室并跳转
    2. 在会诊室里自由发言，AI 扮演患者与其它科室专家
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query
  alias TcmEdu.Mdt.{Case, Participant, Room}

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    student = socket.assigns.current_student

    socket =
      socket
      |> assign(:page_title, "MDT 会诊")
      |> assign(:cases, list_cases(student))
      |> assign(:my_rooms, list_my_rooms(student))

    {:ok, socket}
  end

  @impl true
  def handle_event("start", %{"case_id" => case_id}, socket) do
    student = socket.assigns.current_student

    case create_room_from_case(case_id, student) do
      {:ok, %Room{} = room} ->
        {:noreply, push_navigate(socket, to: "/mdt/rooms/#{room.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "进入会诊失败：#{reason}")}
    end
  end

  # ── helpers ───────────────────────────────────────────────

  defp list_cases(student) do
    Case
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(status == :published)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, cases} -> cases
      _ -> []
    end
  rescue
    _ -> []
  end

  defp list_my_rooms(student) do
    Room
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(owner_id == ^student.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(10)
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, rooms} -> rooms
      _ -> []
    end
  rescue
    _ -> []
  end

  # 创建会诊室：学生以该病例第一个科室角色参与
  defp create_room_from_case(case_id, student) do
    with {:ok, %Case{} = case} <-
           Case.get_case(case_id, actor: student.actor, tenant: student.tenant) do
      depts = case.departments || []
      dept = List.first(depts) || "医生"

      snapshot = %{
        "name" => case.name,
        "complaint" => case.complaint,
        "history" => case.history || "",
        "departments" => depts,
        "expected_conclusion" => case.expected_conclusion
      }

      with {:ok, room} <-
             Room.create_room(
               %{
                 case_id: case.id,
                 owner_id: student.id,
                 status: :open,
                 case_snapshot: snapshot
               },
               actor: student.actor,
               tenant: student.tenant
             ),
           {:ok, _participant} <-
             Participant.create_participant(
               %{
                 room_id: room.id,
                 user_id: student.id,
                 department: dept,
                 display_name: student.name || "医生"
               },
               actor: student.actor,
               tenant: student.tenant
             ) do
        {:ok, room}
      end
    end
  end

  # ── render ────────────────────────────────────────────────

  defp room_status_text(:open), do: "进行中"
  defp room_status_text(:concluded), do: "已汇总"
  defp room_status_text(:abandoned), do: "已结束"
  defp room_status_text(_), do: "—"
end
