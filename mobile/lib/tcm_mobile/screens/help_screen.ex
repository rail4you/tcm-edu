defmodule TcmMobile.Screens.HelpScreen do
  @moduledoc "帮助 —— 学员端功能导览。"

  use Mob.Screen

  alias TcmMobile.UI

  @items [
    {"学习课程", "首页/课程页浏览课程，选修后按章节学习课时，完成随堂测验标记进度。"},
    {"测验考试", "完成阶段测验，交卷即出成绩；错题自动进入错题本，可随时复习。"},
    {"学习问答", "向中医助教提问辨证、方药、经络等问题，获取知识要点与学习建议。"},
    {"模拟患者", "对标准化病人进行四诊问诊，提交辨证后生成临床推理报告。"},
    {"MDT 会诊", "参与多学科病案讨论，发表诊疗意见并学习各科室思路。"},
    {"学习资料", "下载课件与图谱 PDF，离线查看。"}
  ]

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(_assigns) do
    cards =
      Enum.map(@items, fn {title, body} ->
        UI.card([
          ~MOB(<Text text={title} text_size={:base} font_weight="medium" text_color={:on_surface} />),
          ~MOB(<Text text={body} text_size={:sm} text_color={:muted} />)
        ])
      end)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("帮助")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {cards}
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
