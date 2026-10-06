defmodule TcmMobile.Screens.AboutScreen do
  @moduledoc "关于杏宁树。"

  use Mob.Screen

  alias TcmMobile.UI

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(_assigns) do
    intro =
      UI.card([
        ~MOB(<Text
  text="杏宁树学员端基于 Mob（BEAM-on-device）构建：全部界面与业务逻辑以 Elixir 编写，原生运行于 iOS 与 Android。"
  text_size={:sm}
  text_color={:on_surface}
/>),
        ~MOB(<Text text="数据层当前为离线本地模式；接入后端 JSON API 后自动切换远程数据。" text_size={:sm} text_color={:muted} />)
      ])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("关于")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Spacer size={:space_lg} />
          <Box fill_width={true} align={:center}>
            <Box
              width={72}
              height={72}
              corner_radius={:radius_lg}
              background={:primary}
              align={:center}
            >
              <Text text="杏" text_size={:"3xl"} text_color={:on_primary} font_weight="bold" />
            </Box>
          </Box>
          <Text
            text="杏宁树"
            fill_width={true}
            text_align="center"
            text_size={:"2xl"}
            font_weight="bold"
            text_color={:on_surface}
          />
          <Text
            text="中医学院 · 学员端 v0.1.0"
            fill_width={true}
            text_align="center"
            text_size={:sm}
            text_color={:muted}
          />
          <Spacer size={:space_md} />
          {intro}
          <Text
            text="Powered by Elixir · BEAM on device"
            fill_width={true}
            text_align="center"
            text_size={:xs}
            text_color={:muted}
          />
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}
end
