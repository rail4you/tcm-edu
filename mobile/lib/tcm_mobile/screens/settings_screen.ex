defmodule TcmMobile.Screens.SettingsScreen do
  @moduledoc "设置 —— 主题与数据源（本地切换，运行期生效）。"

  use Mob.Screen

  alias TcmMobile.UI

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :source, TcmMobile.Api.source())}
  end

  @impl true
  def render(assigns) do
    about_card =
      UI.card([
        ~MOB(<Text text="杏宁树 v0.1.0" text_size={:base} text_color={:on_surface} />),
        ~MOB(<Text text="数据源切换为远程模式后需后端提供 JSON API（见 TcmMobile.Api）。" text_size={:sm} text_color={:muted} />)
      ])

    source_label =
      if assigns.source == :local, do: "本地离线数据（默认）", else: "远程 API"

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("设置")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {UI.section_label("数据源")}
          <Row gap={:space_sm}>
            {source_option(:local, @source, "离线数据")}
            {source_option(:remote, @source, "远程 API")}
          </Row>
          <Text text={source_label} text_size={:xs} text_color={:muted} />
          <Spacer size={:space_md} />
          {UI.section_label("关于")}
          {about_card}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp source_option(key, current, label) do
    tap = {self(), {:source, key}}
    selected = key == current
    bg = if selected, do: :primary, else: :surface
    fg = if selected, do: :on_primary, else: :on_surface

    ~MOB"""
    <Box background={bg} corner_radius={:radius_md} padding={:space_md} weight={1} on_tap={tap}>
      <Text text={label} text_size={:base} text_color={fg} text_align="center" />
    </Box>
    """
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:source, source}}, socket) do
    Application.put_env(:tcm_mobile, :api_source, source)
    {:noreply, Mob.Socket.assign(socket, :source, source)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
