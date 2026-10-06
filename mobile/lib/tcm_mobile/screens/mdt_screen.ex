defmodule TcmMobile.Screens.MdtScreen do
  @moduledoc "MDT 会诊列表。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :rooms, Api.list_mdt_rooms())}
  end

  @impl true
  def render(assigns) do
    cards = Enum.map(assigns.rooms, &room_card/1)

    hint_card =
      UI.card([
        ~MOB(<Text text="多学科会诊训练：围绕真实病案，与各科室医师共同讨论诊疗方案。" text_size={:sm} text_color={:muted} />)
      ])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("MDT 会诊")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {hint_card}
          {cards}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp room_card(room) do
    tap = {self(), {:room, room.id}}
    active? = room.status == :active
    status_bg = if active?, do: 0x1F00B86B, else: :surface_raised
    status_fg = if active?, do: :primary, else: :muted
    status_label = if active?, do: "进行中", else: "待开始"

    UI.card(
      [
        ~MOB"""
        <Row gap={:space_sm} align={:center}>
          <Text
            text={room.title}
            text_size={:base}
            font_weight="medium"
            text_color={:on_surface}
            weight={1}
            max_lines={2}
          />
          <Box
            background={status_bg}
            fill_width={false}
            corner_radius={:radius_pill}
            padding_top={4}
            padding_bottom={4}
            padding_left={:space_sm}
            padding_right={:space_sm}
          >
            <Text text={status_label} text_size={:xs} text_color={status_fg} font_weight="medium" />
          </Box>
        </Row>
        """,
        ~MOB(<Text text={"病案：#{room.patient_summary}"} text_size={:sm} text_color={:muted} max_lines={2} />),
        ~MOB"""
        <Row gap={:space_sm} align={:center}>
          <Icon name="user" text_size={14} text_color={:muted} />
          <Text
            text={"#{length(room.participants)} 位科室医师 · #{length(room.messages)} 条讨论"}
            text_size={:xs}
            text_color={:muted}
          />
        </Row>
        """
      ],
      on_tap: tap,
      gap: 8
    )
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:room, room_id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.MdtRoomScreen, %{room_id: room_id})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
