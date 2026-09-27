defmodule TcmEduWeb.TeacherMdtLive do
  @moduledoc """
  教师端「MDT 会诊」页 at `/teacher/mdt`。

  从 mock 模板一键创建并发布 MCU 病例，供学生在 `/mdt` 选择进入会诊。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query
  alias TcmEdu.Mdt.{Case, Conclusion, Message, Room}
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
      |> assign(:show_form, false)
      |> assign(:case_form, case_form(%{}))
      |> assign(:expanded_case_id, nil)
      |> assign(:viewing_room, nil)
      |> assign(:viewing_messages, [])
      |> assign(:viewing_conclusion, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("open-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign(:case_form, case_form(%{}))}
  end

  def handle_event("close-form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("validate-case", %{"case" => params}, socket) do
    {:noreply, assign(socket, :case_form, case_form(params))}
  end

  def handle_event("save-case", %{"case" => params}, socket) do
    teacher = socket.assigns.current_teacher
    changeset = case_changeset(params)

    if changeset.valid? do
      attrs = %{
        name: get_field(changeset, :name) |> String.trim(),
        scenario_title: get_field(changeset, :scenario_title) |> empty_to_nil(),
        complaint: get_field(changeset, :complaint) |> String.trim(),
        history: get_field(changeset, :history) |> empty_to_nil(),
        departments: parse_departments(get_field(changeset, :departments)),
        expected_conclusion: get_field(changeset, :expected_conclusion) |> empty_to_nil(),
        status: :published,
        created_by_id: teacher.id,
        created_by_email: to_string(teacher.email)
      }

      case Case.create_case(attrs, actor: teacher.actor, tenant: teacher.tenant) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:show_form, false)
           |> load_cases()
           |> put_flash(:info, "病例已创建并发布")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, "创建失败：#{ash_message(error)}")}
      end
    else
      {:noreply, assign(socket, :case_form, Phoenix.Component.to_form(changeset, as: "case"))}
    end
  end

  def handle_event("toggle-rooms", %{"id" => case_id}, socket) do
    expanded = if socket.assigns.expanded_case_id == case_id, do: nil, else: case_id
    {:noreply, assign(socket, :expanded_case_id, expanded)}
  end

  def handle_event("open-room", %{"id" => room_id}, socket) do
    teacher = socket.assigns.current_teacher
    room = Enum.find(socket.assigns.rooms, &(&1.id == room_id))

    if room do
      {:noreply,
       socket
       |> assign(:viewing_room, room)
       |> assign(:viewing_messages, list_messages(room, teacher))
       |> assign(:viewing_conclusion, load_conclusion(room, teacher))}
    else
      {:noreply, put_flash(socket, :error, "会诊记录不存在")}
    end
  end

  def handle_event("close-room", _params, socket) do
    {:noreply,
     socket
     |> assign(:viewing_room, nil)
     |> assign(:viewing_messages, [])
     |> assign(:viewing_conclusion, nil)}
  end

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
    |> Ash.Query.load([:message_count])
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

  defp case_form(params) do
    params |> case_changeset() |> Phoenix.Component.to_form(as: "case")
  end

  defp case_changeset(params) do
    types = %{
      name: :string,
      scenario_title: :string,
      complaint: :string,
      history: :string,
      departments: :string,
      expected_conclusion: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:name, :complaint])
    |> Ecto.Changeset.validate_length(:name, max: 100)
  end

  defp get_field(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil

  defp empty_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp empty_to_nil(value), do: value

  defp parse_departments(nil), do: []

  defp parse_departments(value) when is_binary(value) do
    value
    |> String.split(~r/[,，、\s]+/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_departments(_), do: []

  defp rooms_for(rooms, case_id) do
    Enum.filter(rooms || [], &(&1.case_id == case_id))
  end

  defp list_messages(room, teacher) do
    Message
    |> Ash.Query.for_read(:for_room, %{room_id: room.id},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.read(actor: teacher.actor, tenant: teacher.tenant)
    |> case do
      {:ok, messages} -> messages
      _ -> []
    end
  rescue
    _ -> []
  end

  defp load_conclusion(room, teacher) do
    Conclusion
    |> Ash.Query.for_read(:read, %{},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.Query.filter(room_id == ^room.id)
    |> Ash.read_one(actor: teacher.actor, tenant: teacher.tenant)
    |> case do
      {:ok, %Conclusion{} = conclusion} -> conclusion
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp role_label("patient"), do: "患者（AI）"
  defp role_label("system"), do: "系统"
  defp role_label("student:" <> dept), do: dept <> "医生"
  defp role_label("dept:" <> dept), do: dept <> "（AI 专家）"
  defp role_label(role), do: role

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end

  defp rooms_label(%Room{} = room) do
    "#{room.case_snapshot["name"] || "会诊"} · #{status_text(room.status)} · #{message_count(room)} 条"
  end

  defp message_count(%{message_count: %Ash.NotLoaded{}}), do: "—"
  defp message_count(%{message_count: nil}), do: "—"
  defp message_count(%{message_count: count}), do: to_string(count)

  defp status_text(:open), do: "进行中"
  defp status_text(:concluded), do: "已汇总"
  defp status_text(:abandoned), do: "已结束"
  defp status_text(_), do: "—"

  # ── render ────────────────────────────────────────────────
end
