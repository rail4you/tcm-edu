defmodule TcmEduWeb.StudentMdtRoomLive do
  @moduledoc """
  学生端 MDT 会诊室 at `/mdt/rooms/:id`.

  * 顶部：病例快照 + 参与者角色（本人科室高亮，未认领科室由 AI 扮演）
  * 中：会诊讨论流（患者 / 各科室 / 学员消息带角色标签）
  * 底：发言框 + 「结束并汇总结论」

  学生每发一条，AI 依次以「患者」和每个未认领科室的专家身份补充发言，
  营造多学科同台讨论的效果。「结束并汇总结论」调用 `AI.MdtFacilitator.summarize/1`
  生成会诊结论并落库。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.AI.MdtFacilitator
  alias TcmEdu.Mdt.{Conclusion, Message, Participant, Room}

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    student = socket.assigns.current_student

    case load_room(room_id, student) do
      {:ok, room} ->
        if room.owner_id != student.id do
          {:ok, push_navigate(socket, to: "/mdt")}
        else
          participants = load_participants(room, student)

          socket =
            socket
            |> assign(:page_title, "MDT 会诊室")
            |> assign(:room, room)
            |> assign(:messages, load_messages(room, student))
            |> assign(:participants, participants)
            |> assign(:my_dept, my_dept_of(participants, student))
            |> assign(:form, message_form())
            |> assign(:thinking, false)
            |> assign(:run_ref, nil)
            |> assign(:concluding, false)

          {:ok, socket}
        end

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: "/mdt")}
    end
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign(socket, :form, message_form(params))}
  end

  def handle_event("send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content || "")
    student = socket.assigns.current_student

    cond do
      content == "" -> {:noreply, socket}
      socket.assigns.room.status != :open -> {:noreply, put_flash(socket, :info, "会诊已结束")}
      socket.assigns.thinking -> {:noreply, put_flash(socket, :info, "AI 正在回应，请稍候")}
      true -> do_send(socket, content, student)
    end
  end

  def handle_event("conclude", _params, socket) do
    student = socket.assigns.current_student

    cond do
      socket.assigns.concluding -> {:noreply, socket}
      length(socket.assigns.messages) < 2 -> {:noreply, put_flash(socket, :error, "至少先进行几轮讨论再汇总")}
      true -> do_conclude(socket, student)
    end
  end

  @impl true
  def handle_info({:mdt_done, ref, _state}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:thinking, false)
       |> assign(:run_ref, nil)
       |> do_refresh_after_ai()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:mdt_error, ref, message}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:thinking, false)
       |> assign(:run_ref, nil)
       |> put_flash(:error, "AI 出错了：#{message}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:conclude_done, ref, _room_id}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:concluding, false)
       |> assign(:run_ref, nil)
       |> refresh_room_assign()}
    else
      {:noreply, socket}
    end
  end

  # ── send ──────────────────────────────────────────────────

  defp do_send(socket, content, student) do
    room = socket.assigns.room
    lv = self()
    ref = make_ref()

    with :ok <- store_message(room, "student:#{my_dept(socket)}", content, student) do
      socket =
        socket
        |> assign(:thinking, true)
        |> assign(:run_ref, ref)
        |> assign(:form, message_form())
        |> assign(
          :messages,
          socket.assigns.messages ++
            [%{role: "student:#{my_dept(socket)}", content: content}]
        )

      Task.start(fn -> run_ai_chain(lv, ref, room, socket.assigns, content, student) end)
      {:noreply, socket}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "发送失败：#{reason}")}
    end
  end

  # AI 以患者 + 每个未认领科室依次发言并落库
  defp run_ai_chain(lv_pid, ref, room, assigns, student_msg, student) do
    history = assigns.messages
    claimed = Enum.map(assigns.participants, & &1.department)
    depts = room.case_snapshot["departments"] || []
    other_depts = depts |> Enum.reject(&(&1 in claimed)) |> Enum.take(3)

    roles = ["patient" | Enum.map(other_depts, &"dept:#{&1}")]

    result =
      Enum.reduce_while(roles, {:ok, %{}}, fn role, {:ok, acc} ->
        case MdtFacilitator.respond(
               case_snapshot: room.case_snapshot,
               role: role,
               history: history ++ (acc[:replies] || []),
               student_message: student_msg
             ) do
          {:ok, %{reply: reply}} when is_binary(reply) and reply != "" ->
            case store_message(room, role, reply, student) do
              :ok -> {:cont, {:ok, Map.update(acc, :replies, [reply], &(&1 ++ [reply]))}}
              _ -> {:halt, {:error, :persist}}
            end

          {:error, reason} ->
            Logger.warning("[MdtRoom] role #{role} failed: #{inspect(reason)}")
            {:halt, {:error, reason}}
        end
      end)

    if Process.alive?(lv_pid) do
      send(
        lv_pid,
        if(elem(result, 0) == :ok, do: {:mdt_done, ref, :ok}, else: {:mdt_error, ref, "AI 回应失败"})
      )
    end
  rescue
    e ->
      if Process.alive?(lv_pid), do: send(lv_pid, {:mdt_error, ref, Exception.message(e)})
  end

  defp do_refresh_after_ai(socket) do
    assign(socket, :messages, load_messages(socket.assigns.room, socket.assigns.current_student))
  end

  # ── conclude ──────────────────────────────────────────────

  defp do_conclude(socket, student) do
    room = socket.assigns.room
    lv = self()
    ref = make_ref()

    socket = socket |> assign(:concluding, true) |> assign(:run_ref, ref)

    Task.start(fn ->
      case MdtFacilitator.summarize(
             case_snapshot: room.case_snapshot,
             history:
               Enum.map(load_messages(room, student), fn m ->
                 %{role: m.role, content: m.content}
               end)
           ) do
        {:ok, result} ->
          store_conclusion(room, result, student)
          :ok

        {:error, reason} ->
          Logger.warning("[MdtRoom] summarize failed: #{inspect(reason)}")
          :error
      end

      if Process.alive?(lv), do: send(lv, {:conclude_done, ref, room.id})
    end)

    {:noreply, socket}
  end

  defp store_conclusion(room, result, student) do
    Conclusion
    |> Ash.Changeset.for_create(
      :create,
      %{
        room_id: room.id,
        primary_diagnosis: result.primary_diagnosis,
        differential: result.differential,
        treatment: result.treatment,
        roles_considered: result.roles_considered,
        summary: result.summary,
        model: TcmEdu.AI.text_model()
      },
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.create()

    room
    |> Ash.Changeset.for_update(:conclude, %{}, actor: student.actor, tenant: student.tenant)
    |> Ash.update()
  end

  defp refresh_room_assign(socket) do
    case load_room(socket.assigns.room.id, socket.assigns.current_student) do
      {:ok, room} ->
        socket
        |> assign(:room, room)
        |> assign(:messages, load_messages(room, socket.assigns.current_student))

      _ ->
        socket
    end
  end

  # ── data ──────────────────────────────────────────────────

  defp load_room(id, student) do
    Room
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.limit(1)
    |> Ash.Query.load([:conclusion])
    |> Ash.read_one(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, %Room{} = room} -> {:ok, room}
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp load_messages(%Room{id: room_id}, student) do
    Message
    |> Ash.Query.for_read(:for_room, %{room_id: room_id},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, messages} -> messages
      _ -> []
    end
  rescue
    _ -> []
  end

  defp load_participants(%Room{id: room_id}, student) do
    Participant
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, participants} -> participants
      _ -> []
    end
  rescue
    _ -> []
  end

  defp store_message(%Room{id: room_id}, role, content, student) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{room_id: room_id, role: role, content: content, author_id: student.id},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.create()
    |> case do
      {:ok, _} -> :ok
      {:error, e} -> {:error, Exception.message(e)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp my_dept(socket) do
    case Enum.find(
           socket.assigns.participants,
           &(&1.user_id == socket.assigns.current_student.id)
         ) do
      nil -> "医生"
      p -> p.department
    end
  end

  defp my_dept_of(participants, student) do
    case Enum.find(participants, &(&1.user_id == student.id)) do
      nil -> "医生"
      p -> p.department
    end
  end

  defp message_form(params \\ %{}) do
    {%{}, %{content: :string}}
    |> Ecto.Changeset.cast(params, [:content])
    |> Ecto.Changeset.validate_required([:content])
    |> Phoenix.Component.to_form(as: "message")
  end

  # ── render ────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, default: ""

  defp kv(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200/30 p-3">
      <p class="text-xs text-base-content/50">{@label}</p>
      <p class="mt-1 text-sm">{if @value == "", do: "—", else: @value}</p>
    </div>
    """
  end

  # ── label helpers ─────────────────────────────────────────

  defp missing_depts(room, participants) do
    depts = room.case_snapshot["departments"] || []
    claimed = Enum.map(participants, & &1.department)
    depts |> Enum.reject(&(&1 in claimed)) |> Enum.take(3)
  end

  defp role_is_patient(role), do: role in ["patient", "system"]

  defp is_student_msg(message, student) do
    message.role == "student:#{student.id}" or
      String.starts_with?(message.role, "student:")
  end

  defp avatar_text("patient"), do: "患"
  defp avatar_text("system"), do: "AI"
  defp avatar_text(role), do: role |> String.split(":") |> List.last() |> String.slice(0, 1)

  defp role_label(role, participants) do
    case String.split(role, ":", parts: 2) do
      ["patient", _] ->
        "患者（AI）"

      ["student", dept] ->
        case Enum.find(participants, &(&1.department == dept)) do
          nil -> dept
          p -> p.display_name || dept
        end

      ["dept", dept] ->
        "#{dept}（AI 专家）"

      [other] ->
        other
    end
  end

  defp room_status_text(:open), do: "进行中"
  defp room_status_text(:concluded), do: "已汇总"
  defp room_status_text(:abandoned), do: "已结束"
  defp room_status_text(_), do: "—"

  defp status_badge(:open), do: "badge-info"
  defp status_badge(:concluded), do: "badge-success"
  defp status_badge(:abandoned), do: "badge-ghost"
  defp status_badge(_), do: "badge-ghost"
end
