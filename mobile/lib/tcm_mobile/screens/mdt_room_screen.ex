defmodule TcmMobile.Screens.MdtRoomScreen do
  @moduledoc "MDT 会诊房间 —— 病案信息、参与医师、讨论消息流。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{room_id: room_id}, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:room_id, room_id)
     |> Mob.Socket.assign(:data, Api.mdt_room(room_id))
     |> Mob.Socket.assign(:draft, "")}
  end

  @impl true
  def render(assigns) do
    room = assigns.data.room
    send_tap = {self(), :send}
    draft_change = {self(), :draft}

    case_card =
      UI.card([
        ~MOB(<Text text={room.title} text_size={:base} font_weight="medium" text_color={:on_surface} />),
        ~MOB(<Text text={"病案：#{room.patient_summary}"} text_size={:sm} text_color={:muted} />)
      ])

    doctor_chips =
      Enum.map(room.participants, fn p ->
        ~MOB(<Box
  background={:surface_raised}
  corner_radius={:radius_pill}
  padding_top={:space_xs}
  padding_bottom={:space_xs}
  padding_left={:space_md}
  padding_right={:space_md}
  fill_width={false}
>
  <Text text={"#{p.name} · #{p.department}"} text_size={:xs} text_color={:on_surface} />
</Box>)
      end)

    doctor_card =
      UI.card([
        ~MOB(<Text text="参与医师" text_size={:xs} font_weight="medium" text_color={:primary} />),
        %{
          type: :wrap,
          props: %{spacing: :space_sm, run_spacing: :space_sm},
          children: doctor_chips
        }
      ])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("会诊讨论")}
      <Scroll weight={1} padding={:space_md} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {case_card}
          {doctor_card}
          {UI.section_label("讨论记录")}
          <Column gap={:space_sm}>
            {Enum.map(@data.messages, fn m -> mdt_bubble(%{m: m}) end)}
          </Column>
        </Column>
      </Scroll>
      <Row
        gap={:space_sm}
        padding={:space_md}
        background={:surface}
        border_color={:border}
        border_top_width={1}
        align={:center}
      >
        <TextField value={@draft} placeholder="发表你的诊疗意见…" on_change={draft_change} weight={1} />
        <Box on_tap={send_tap} background={:primary} corner_radius={:radius_pill} padding={:space_md}>
          <Icon name="forward" text_size={18} text_color={:on_primary} />
        </Box>
      </Row>
    </Column>
    """
  end

  defp mdt_bubble(assigns) do
    {bg, fg, align} =
      case assigns.m.role do
        :student -> {:primary, :on_primary, :end}
        :doctor -> {:surface_raised, :on_surface, :start}
      end

    label =
      if assigns.m.role == :doctor, do: "#{assigns.m.speaker}（#{assigns.m.department}）", else: "我"

    ~MOB"""
    <Column fill_width={true} align={align}>
      <Text text={label} text_size={:xs} text_color={:muted} padding_bottom={2} />
      <Box background={bg} corner_radius={:radius_lg} padding={:space_md} fill_width={false}>
        <Text text={assigns.m.text} text_size={:base} text_color={fg} />
      </Box>
      <Text text={assigns.m.time} text_size={:xs} text_color={:muted} padding_top={2} />
    </Column>
    """
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:change, :draft, value}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :draft, value)}

  def handle_info({:tap, :send}, socket) do
    text = String.trim(socket.assigns.draft)

    if text == "" do
      {:noreply, socket}
    else
      Api.send_mdt(socket.assigns.room_id, text)

      {:noreply,
       socket
       |> Mob.Socket.assign(:data, Api.mdt_room(socket.assigns.room_id))
       |> Mob.Socket.assign(:draft, "")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
