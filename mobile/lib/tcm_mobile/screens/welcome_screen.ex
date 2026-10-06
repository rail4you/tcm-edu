defmodule TcmMobile.Screens.WelcomeScreen do
  @moduledoc "启动根屏 —— 品牌展示 + 登录 / 游客入口。"

  use Mob.Screen

  @features [
    {"课", "体系课程", "按章节学习，随堂测验"},
    {"诊", "模拟患者", "四诊接诊，生成推理报告"},
    {"问", "学习问答", "随时提问，答疑解惑"},
    {"合", "MDT 会诊", "多学科病案讨论训练"}
  ]

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(_assigns) do
    login_tap = {self(), :login}
    guest_tap = {self(), :guest}

    feature_cards =
      Enum.map(@features, fn {glyph, title, desc} ->
        %{
          type: :row,
          props: %{
            fill_width: true,
            align: :center,
            gap: :space_md,
            background: :surface,
            corner_radius: :radius_lg,
            padding: :space_md,
            border_color: :border,
            border_width: 1
          },
          children: [
            %{
              type: :box,
              props: %{
                width: 40,
                height: 40,
                corner_radius: :radius_md,
                background: 0x1F00B86B,
                align: :center
              },
              children: [
                %{
                  type: :text,
                  props: %{
                    text: glyph,
                    text_size: :base,
                    font_weight: "bold",
                    text_color: :primary
                  },
                  children: []
                }
              ]
            },
            %{
              type: :column,
              props: %{gap: 2, weight: 1},
              children: [
                %{
                  type: :text,
                  props: %{
                    text: title,
                    text_size: :base,
                    font_weight: "medium",
                    text_color: :on_surface
                  },
                  children: []
                },
                %{
                  type: :text,
                  props: %{text: desc, text_size: :sm, text_color: :muted},
                  children: []
                }
              ]
            }
          ]
        }
      end)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Spacer size={:space_xl} />
          <Column fill_width={true} gap={:space_sm}>
            <Box fill_width={true} align={:center}>
              <Box
                width={88}
                height={88}
                corner_radius={:radius_lg}
                background={:primary}
                align={:center}
              >
                <Text text="杏" text_size={:"4xl"} text_color={:on_primary} font_weight="bold" />
              </Box>
            </Box>
            <Spacer size={:space_xs} />
            <Text
              text="杏宁树"
              fill_width={true}
              text_align="center"
              text_size={:"3xl"}
              font_weight="bold"
              text_color={:on_surface}
            />
            <Text
              text="中医学院 · 学员端"
              fill_width={true}
              text_align="center"
              text_size={:base}
              text_color={:muted}
            />
          </Column>
          <Spacer size={:space_md} />
          <Column gap={:space_sm} fill_width={true}>
            {feature_cards}
          </Column>
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
      <Column gap={:space_sm} fill_width={true} padding={:space_lg}>
        <Button text="学员登录" on_tap={login_tap} />
        <Button text="游客浏览" on_tap={guest_tap} background={:surface} text_color={:primary} />
      </Column>
    </Column>
    """
  end

  @impl true
  def handle_info({:tap, :login}, socket) do
    # 会话已恢复（远程 token 有效）就直接进首页，免得再输一遍密码
    if TcmMobile.Api.logged_in?() do
      {:noreply, Mob.Socket.reset_to(socket, :home, %{}, scope: :all)}
    else
      {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.LoginScreen)}
    end
  end

  def handle_info({:tap, :guest}, socket) do
    {:noreply, Mob.Socket.reset_to(socket, :home, %{}, scope: :all)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
