defmodule TcmMobile.Screens.LoginScreen do
  @moduledoc "学员登录 —— 校验通过后 `reset_to :home`（scope: :all 丢弃所有旧栈）。"

  use Mob.Screen

  alias TcmMobile.UI

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, email: "", password: "", error: nil, busy: false)}
  end

  @impl true
  def render(assigns) do
    submit = {self(), :submit}
    email_change = {self(), :email}
    pass_change = {self(), :password}
    error = assigns.error

    error_node =
      if error do
        ~MOB(<Box background={0x1FBA1A1A} corner_radius={:radius_md} padding={:space_md} fill_width={true}>
  <Text text={error} text_size={:sm} text_color={:error} />
</Box>)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("学员登录")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Spacer size={:space_lg} />
          <Box
            width={64}
            height={64}
            corner_radius={:radius_lg}
            background={:primary}
            align={:center}
          >
            <Text text="岐" text_size={:"3xl"} text_color={:on_primary} font_weight="bold" />
          </Box>
          <Column gap={4} fill_width={true}>
            <Text text="欢迎回来" text_size={:"2xl"} font_weight="bold" text_color={:on_surface} />
            <Text text="登录后同步学习进度与测验记录" text_size={:sm} text_color={:muted} />
          </Column>
          <Spacer size={:space_sm} />
          <Column gap={:space_xs}>
            <Text text="邮箱" text_size={:sm} font_weight="medium" text_color={:on_surface} />
            <TextField
              value={assigns.email}
              placeholder="student@tcm.edu.cn"
              on_change={email_change}
              keyboard_type={:email}
            />
          </Column>
          <Column gap={:space_xs}>
            <Text text="密码" text_size={:sm} font_weight="medium" text_color={:on_surface} />
            <TextField
              value={assigns.password}
              placeholder="••••••"
              secure={true}
              on_change={pass_change}
            />
          </Column>
          {error_node}
          <Spacer size={:space_xs} />
          <Button
            text={if assigns.busy, do: "登录中…", else: "登录"}
            on_tap={submit}
            disabled={assigns.busy}
          />
          {UI.card([~MOB(<Text text="演示账号：student@tcm.edu.cn　密码：123456" text_size={:xs} text_color={:muted} text_align="center" />)], background: :surface_raised)}
        </Column>
      </Scroll>
    </Column>
    """
  end

  @impl true
  def handle_info({:change, :email, value}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :email, value)}

  def handle_info({:change, :password, value}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :password, value)}

  def handle_info({:tap, :submit}, socket) do
    case TcmMobile.Api.login(socket.assigns.email, socket.assigns.password) do
      :ok ->
        {:noreply, Mob.Socket.reset_to(socket, :home, %{}, scope: :all)}

      {:error, reason} ->
        {:noreply, Mob.Socket.assign(socket, :error, reason)}
    end
  end

  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}
end
