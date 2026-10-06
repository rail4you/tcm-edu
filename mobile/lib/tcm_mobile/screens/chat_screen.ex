defmodule TcmMobile.Screens.ChatScreen do
  @moduledoc """
  学习问答 —— 与中医助教对话（本地规则式 AI，预留远程大模型）。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket |> Mob.Socket.assign(:messages, Api.chat_messages()) |> Mob.Socket.assign(:draft, "")}
  end

  @impl true
  def render(assigns) do
    send_tap = {self(), :send}
    draft_change = {self(), :draft}

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("学习问答")}
      <Scroll weight={1} padding={:space_md} fill_width={true} id="chat">
        <Column gap={:space_sm} fill_width={true}>
          {if @messages == [] do
            UI.card([~MOB(<Text text="你好，我是中医学习助教。可以问我辨证、方药、经络、病案等中医问题。" text_size={:base} text_color={:on_surface} />)])
          else
            Enum.map(@messages, fn m -> bubble(%{m: m}) end)
          end}
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
        <TextField value={@draft} placeholder="输入你的问题…" on_change={draft_change} weight={1} />
        <Box
          on_tap={send_tap}
          fill_width={false}
          background={:primary}
          corner_radius={:radius_pill}
          padding={:space_md}
        >
          <Icon name="forward" text_size={18} text_color={:on_primary} />
        </Box>
      </Row>
    </Column>
    """
  end

  defp bubble(assigns) do
    is_user = assigns.m.role == :user
    bg = if is_user, do: :primary, else: :surface_raised
    fg = if is_user, do: :on_primary, else: :on_surface
    align = if is_user, do: :trailing, else: :leading

    ~MOB"""
    <Box fill_width={true} align={align}>
      <Column gap={2}>
        <Box background={bg} corner_radius={:radius_lg} padding={:space_md} fill_width={false}>
          <Text text={assigns.m.text} text_size={:base} text_color={fg} />
        </Box>
        <Text text={assigns.m.time} text_size={:xs} text_color={:muted} padding_top={2} />
      </Column>
    </Box>
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
      messages = Api.send_chat(text)

      {:noreply,
       socket |> Mob.Socket.assign(:messages, messages) |> Mob.Socket.assign(:draft, "")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
