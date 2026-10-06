defmodule TcmMobile.Screens.ProfileScreen do
  @moduledoc """
  我的 tab —— 学员信息、通知、学习资料、设置、退出登录。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @entries [
    %{key: :notifications, glyph: "通", label: "通知", tint: :primary, badge: true},
    %{key: :downloads, glyph: "资", label: "学习资料", tint: :secondary},
    %{key: :courses, glyph: "课", label: "浏览课程", tint: :gold},
    %{key: :about, glyph: "关", label: "关于杏宁树", tint: :teal},
    %{key: :settings, glyph: "设", label: "设置", tint: :plum},
    %{key: :help, glyph: "助", label: "帮助", tint: :secondary}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:student, Api.student())
     |> Mob.Socket.assign(:unread, Api.unread_count())}
  end

  @impl true
  def render(assigns) do
    student = assigns.student
    unread = assigns.unread

    tiles =
      Enum.map(@entries, fn e ->
        badge = if Map.get(e, :badge, false) and unread > 0, do: "#{unread} 条未读", else: nil

        UI.list_tile(UI.glyph_tile(e.glyph, e.tint, 40), e.label, badge,
          on_tap: {self(), {:entry, e.key}}
        )
      end)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {UI.app_bar("我的")}
          {student_card(student)}
          <Spacer size={:space_xs} />
          <Column gap={:space_sm} fill_width={true}>
            {tiles}
          </Column>
          {auth_section(student)}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
      {UI.tab_bar(:profile)}
    </Column>
    """
  end

  defp student_card(nil) do
    login_tap = {self(), :login}

    UI.card([
      ~MOB(<Text text="未登录" text_size={:lg} font_weight="bold" text_color={:on_surface} />),
      ~MOB(<Text text="登录后同步学习进度，使用测验、模拟患者与 MDT 功能。" text_size={:sm} text_color={:muted} />),
      ~MOB(<Button text="去登录" on_tap={login_tap} />)
    ])
  end

  defp student_card(student) do
    ~MOB"""
    <Box background={:primary} corner_radius={:radius_lg} padding={:space_lg} fill_width={true}>
      <Row gap={:space_md} align={:center}>
        <Box
          width={56}
          height={56}
          corner_radius={:radius_pill}
          background={0x33FFFFFF}
          align={:center}
        >
          <Text
            text={student.avatar || "学"}
            text_size={:xl}
            font_weight="bold"
            text_color={:on_primary}
          />
        </Box>
        <Column gap={2} weight={1}>
          <Text text={student.name} text_size={:xl} font_weight="bold" text_color={:on_primary} />
          <Text text={student.email} text_size={:sm} text_color={0xCCFFFFFF} />
        </Column>
      </Row>
    </Box>
    """
  end

  defp auth_section(nil), do: %{type: :spacer, props: %{}, children: []}

  defp auth_section(_student) do
    logout_tap = {self(), :logout}

    ~MOB"""
    <Column gap={:space_sm} fill_width={true}>
      <Button text="退出登录" on_tap={logout_tap} background={:surface} text_color={:error} />
      <Text
        text="杏宁树 v0.1.0 · BEAM on device"
        text_size={:xs}
        text_color={:muted}
        text_align="center"
      />
    </Column>
    """
  end

  @impl true
  def handle_info({:tap, {:switch_tab, tab}}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, tab)}
  end

  def handle_info({:tap, :login}, socket) do
    {:noreply, Mob.Socket.reset_to(socket, TcmMobile.Screens.LoginScreen, %{}, scope: :all)}
  end

  def handle_info({:tap, {:entry, :notifications}}, socket) do
    Api.mark_notifications_read()
    {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.NotificationsScreen)}
  end

  def handle_info({:tap, {:entry, :downloads}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.DownloadsScreen)}

  def handle_info({:tap, {:entry, :courses}}, socket),
    do: {:noreply, Mob.Socket.switch_tab(socket, :courses)}

  def handle_info({:tap, {:entry, :about}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.AboutScreen)}

  def handle_info({:tap, {:entry, :settings}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.SettingsScreen)}

  def handle_info({:tap, {:entry, :help}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.HelpScreen)}

  def handle_info({:tap, :logout}, socket) do
    Api.logout()
    {:noreply, Mob.Socket.reset_to(socket, TcmMobile.Screens.WelcomeScreen, %{}, scope: :all)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
