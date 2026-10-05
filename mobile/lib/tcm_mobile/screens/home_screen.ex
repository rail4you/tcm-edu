defmodule TcmMobile.Screens.HomeScreen do
  @moduledoc """
  首页 tab —— 问候、学习统计、功能入口、分类、热门课程。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @entries [
    %{key: :exams, glyph: "测", label: "测验考试", tint: :gold},
    %{key: :chat, glyph: "问", label: "学习问答", tint: :teal},
    %{key: :sp, glyph: "患", label: "模拟患者", tint: :primary},
    %{key: :mdt, glyph: "诊", label: "MDT 会诊", tint: :plum},
    %{key: :mistakes, glyph: "错", label: "错题本", tint: :error},
    %{key: :notifications, glyph: "通", label: "通知", tint: :secondary}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:student, Api.student())
     |> Mob.Socket.assign(:stats, Api.my_stats())
     |> Mob.Socket.assign(:categories, Api.list_categories())
     |> Mob.Socket.assign(:popular, Api.popular_courses())
     |> Mob.Socket.assign(:unread, Api.unread_count())}
  end

  @impl true
  def render(assigns) do
    student = assigns.student
    name = if student, do: student.name, else: "同学"
    stats = assigns.stats
    entries = @entries

    course_taps = Map.new(assigns.popular, fn c -> {c.id, {self(), {:course, c.id}}} end)
    category_taps = Map.new(assigns.categories, fn c -> {c.id, {self(), {:category, c.id}}} end)

    feature_tiles =
      Enum.map(entries, fn e ->
        UI.feature_tile(e.glyph, e.label, e.tint, {self(), {:entry, e.key}})
      end)

    category_chips =
      Enum.map(assigns.categories, fn c ->
        tap = Map.fetch!(category_taps, c.id)
        UI.chip(c.name, false) |> put_tap(tap)
      end)

    course_cards =
      Enum.map(assigns.popular, fn c ->
        UI.course_card(c, Map.fetch!(course_taps, c.id), Api.enrolled?(c.id))
      end)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {UI.app_bar("你好，#{name}", greeting(), {"search", :search})}
          <Row gap={:space_sm}>
            {UI.stat_card("已选课程", "#{stats.courses}", :primary)}
            {UI.stat_card("完成课时", "#{stats.lessons_done}", :secondary)}
            {UI.stat_card("学习时长", "#{div(stats.study_minutes, 60)}h", :gold)}
          </Row>
          <Row gap={:space_sm}>
            {UI.stat_card("连续学习", "#{stats.streak} 天", :teal)}
            {UI.stat_card("错题", "#{stats.mistakes}", :error)}
            {UI.stat_card("未读通知", "#{assigns.unread}", :plum)}
          </Row>
          <Spacer size={:space_xs} />
          {UI.section_header("学习工具")}
          <Row gap={:space_sm}>
            {Enum.at(feature_tiles, 0)}
            {Enum.at(feature_tiles, 1)}
            {Enum.at(feature_tiles, 2)}
          </Row>
          <Row gap={:space_sm}>
            {Enum.at(feature_tiles, 3)}
            {Enum.at(feature_tiles, 4)}
            {Enum.at(feature_tiles, 5)}
          </Row>
          <Spacer size={:space_xs} />
          {UI.section_header("课程分类", "全部", :all_courses)}
          <Wrap spacing={:space_sm} run_spacing={:space_sm}>
            {category_chips}
          </Wrap>
          <Spacer size={:space_xs} />
          {UI.section_header("热门课程", "更多", :all_courses)}
          {course_cards}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
      {UI.tab_bar(:home)}
    </Column>
    """
  end

  defp put_tap(node, tap), do: %{node | props: Map.put(node.props, :on_tap, tap)}

  defp greeting do
    hour = rem(DateTime.utc_now().hour + 8, 24)

    cond do
      hour < 6 -> "夜深了，注意休息"
      hour < 12 -> "早上好，开始今天的研习吧"
      hour < 14 -> "中午好，饭后宜小憩"
      hour < 18 -> "下午好，温故而知新"
      true -> "晚上好，勤学不辍"
    end
  end

  @impl true
  def handle_info({:tap, {:switch_tab, tab}}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, tab)}
  end

  def handle_info({:tap, {:entry, :exams}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.ExamsScreen)}

  def handle_info({:tap, {:entry, :chat}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.ChatScreen)}

  def handle_info({:tap, {:entry, :sp}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.SimulatedPatientScreen)}

  def handle_info({:tap, {:entry, :mdt}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.MdtScreen)}

  def handle_info({:tap, {:entry, :mistakes}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.MistakesScreen)}

  def handle_info({:tap, {:entry, :notifications}}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, TcmMobile.Screens.NotificationsScreen)}

  def handle_info({:tap, {:course, course_id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.CourseDetailScreen, %{course_id: course_id})}
  end

  def handle_info({:tap, {:category, category_id}}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, :courses, mount_params: %{category: category_id})}
  end

  def handle_info({:tap, :all_courses}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, :courses)}
  end

  def handle_info({:tap, :search}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, :courses)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
