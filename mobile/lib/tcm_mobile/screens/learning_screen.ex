defmodule TcmMobile.Screens.LearningScreen do
  @moduledoc """
  学习 tab —— 学习统计、在学课程进度、测验 / 错题 / 模拟患者 / MDT 入口。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @tools [
    %{key: :exams, glyph: "测", label: "测验考试", tint: :gold},
    %{key: :mistakes, glyph: "错", label: "错题本", tint: :error},
    %{key: :chat, glyph: "问", label: "学习问答", tint: :teal},
    %{key: :sp, glyph: "患", label: "模拟患者", tint: :primary},
    %{key: :mdt, glyph: "诊", label: "MDT 会诊", tint: :plum},
    %{key: :downloads, glyph: "资", label: "学习资料", tint: :secondary}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:stats, Api.my_stats())
     |> Mob.Socket.assign(:courses, Api.my_courses())}
  end

  @impl true
  def render(assigns) do
    courses = assigns.courses
    stats = assigns.stats

    course_cards =
      Enum.map(courses, fn c ->
        tap = {self(), {:course, c.id}}

        UI.card(
          [
            UI.list_tile(
              UI.glyph_tile(String.slice(c.title, 0, 1), :primary, 44),
              c.title,
              "#{c.progress.percent}% · 完成 #{length(c.progress.completed)}/#{c.progress.total} 课时",
              trailing: nil
            ),
            UI.progress_bar(c.progress.percent)
          ],
          on_tap: tap,
          gap: 12
        )
      end)

    tool_tiles =
      Enum.map(@tools, fn t ->
        UI.feature_tile(t.glyph, t.label, t.tint, {self(), {:entry, t.key}})
      end)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {UI.app_bar("我的学习", "已选 #{stats.courses} 门 · 完成 #{stats.lessons_done} 课时")}
          <Row gap={:space_sm}>
            {UI.stat_card("在学课程", "#{stats.courses}", :primary)}
            {UI.stat_card("完成课时", "#{stats.lessons_done}", :secondary)}
            {UI.stat_card("连续学习", "#{stats.streak} 天", :gold)}
          </Row>
          {if courses == [], do: not_enrolled(), else: enrolled_section(course_cards)}
          <Spacer size={:space_xs} />
          {UI.section_header("学习工具")}
          <Row gap={:space_sm}>
            {Enum.at(tool_tiles, 0)}
            {Enum.at(tool_tiles, 1)}
            {Enum.at(tool_tiles, 2)}
          </Row>
          <Row gap={:space_sm}>
            {Enum.at(tool_tiles, 3)}
            {Enum.at(tool_tiles, 4)}
            {Enum.at(tool_tiles, 5)}
          </Row>
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
      {UI.tab_bar(:learning)}
    </Column>
    """
  end

  defp not_enrolled do
    browse_tap = {self(), :browse}

    UI.card([
      ~MOB(<Text text="还没有选修课程" text_size={:base} font_weight="medium" text_color={:on_surface} />),
      ~MOB(<Text text="去课程页选一门感兴趣的课程，开始你的中医学习之旅。" text_size={:sm} text_color={:muted} />),
      ~MOB(<Button text="浏览课程" on_tap={browse_tap} />)
    ])
  end

  defp enrolled_section(course_cards) do
    ~MOB"""
    <Column gap={:space_md} fill_width={true}>
      {UI.section_header("在学课程", "全部", :all_courses)}
      {course_cards}
    </Column>
    """
  end

  @impl true
  def handle_info({:tap, {:switch_tab, tab}}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, tab)}
  end

  def handle_info({:tap, {:course, course_id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.CourseDetailScreen, %{course_id: course_id})}
  end

  def handle_info({:tap, :browse}, socket),
    do: {:noreply, Mob.Socket.switch_tab(socket, :courses)}

  def handle_info({:tap, :all_courses}, socket),
    do: {:noreply, Mob.Socket.switch_tab(socket, :courses)}

  def handle_info({:tap, {:entry, :exams}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.ExamsScreen)}

  def handle_info({:tap, {:entry, :mistakes}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.MistakesScreen)}

  def handle_info({:tap, {:entry, :chat}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.ChatScreen)}

  def handle_info({:tap, {:entry, :sp}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.SimulatedPatientScreen)}

  def handle_info({:tap, {:entry, :mdt}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.MdtScreen)}

  def handle_info({:tap, {:entry, :downloads}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.DownloadsScreen)}

  def handle_info(_msg, socket), do: {:noreply, socket}
end
