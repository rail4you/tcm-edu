defmodule TcmMobile.Screens.CourseDetailScreen do
  @moduledoc """
  课程详情 —— 简介、教师、课时列表（按章节）、选课 / 进度。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{course_id: course_id}, _session, socket) do
    course = Api.get_course(course_id)
    enrolled? = Api.enrolled?(course_id)
    progress = Api.progress(course_id)

    {:ok,
     socket
     |> Mob.Socket.assign(:course_id, course_id)
     |> Mob.Socket.assign(:course, course)
     |> Mob.Socket.assign(:enrolled?, enrolled?)
     |> Mob.Socket.assign(:progress, progress)
     |> Mob.Socket.assign(:hint, nil)}
  end

  @impl true
  def render(assigns) do
    course = assigns.course
    lessons = course.lessons
    lesson_taps = Map.new(lessons, fn l -> {l.id, {self(), {:lesson, l.id}}} end)
    continue_tap = {self(), :continue}
    enroll_tap = {self(), :enroll}
    kind_label = %{text: "图文", video: "视频", quiz: "测验"}
    status = if assigns.enrolled?, do: "已选修 · 进度 #{assigns.progress.percent}%", else: "未选修"

    action_button =
      if assigns.enrolled? do
        ~MOB(<Button text="继续学习" on_tap={continue_tap} />)
      else
        ~MOB(<Button text="选修本课程" on_tap={enroll_tap} />)
      end

    hint_node =
      if assigns.hint do
        ~MOB(<Text text={assigns.hint} text_size={:sm} text_color={:error} />)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    teacher_card =
      UI.card([
        ~MOB(<Text text="授课教师" text_size={:xs} font_weight="medium" text_color={:muted} />),
        ~MOB(<Text
  text={"#{course.teacher.name}　#{course.teacher.title}"}
  text_size={:base}
  font_weight="medium"
  text_color={:on_surface}
/>),
        ~MOB(<Text text={course.teacher.specialty} text_size={:sm} text_color={:muted} />)
      ])

    lesson_rows =
      Enum.map(lessons, fn l ->
        tap = Map.fetch!(lesson_taps, l.id)
        done = Api.completed_lesson?(course.id, l.id)
        lesson_row(l, tap, done, Map.fetch!(kind_label, l.kind))
      end)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("课程详情")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Box background={:primary} corner_radius={:radius_lg} padding={:space_lg} fill_width={true}>
            <Column gap={:space_sm}>
              <Text
                text={course.title}
                text_size={:"2xl"}
                font_weight="bold"
                text_color={:on_primary}
              />
              <Text text={course.subtitle} text_size={:base} text_color={0xCCFFFFFF} />
              <Spacer size={:space_xs} />
              <Box
                background={0x33FFFFFF}
                corner_radius={:radius_pill}
                padding_top={4}
                padding_bottom={4}
                padding_left={:space_md}
                padding_right={:space_md}
                fill_width={false}
              >
                <Text text={status} text_size={:sm} text_color={:on_primary} />
              </Box>
            </Column>
          </Box>
          {action_button}
          {hint_node}
          {UI.card([~MOB(<Text text={course.description} text_size={:base} text_color={:on_surface} />)])}
          {teacher_card}
          <Row gap={:space_sm}>
            {Enum.map(course.tags, fn t -> UI.chip(t) end)}
          </Row>
          {UI.section_header("课时内容", "共 #{length(lessons)} 课")}
          <Column gap={:space_sm}>
            {lesson_rows}
          </Column>
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp lesson_row(l, tap, done, kind_label) do
    number_bg = if done, do: 0x1F3E5C46, else: 0x1F9A2E22
    number_fg = if done, do: :secondary, else: :primary

    trailing =
      if done do
        ~MOB(<Icon name="check" text_size={18} text_color={:secondary} />)
      else
        ~MOB(<Icon name="chevron_right" text_size={18} text_color={:muted} />)
      end

    leading =
      ~MOB(<Box width={36} height={36} corner_radius={:radius_pill} background={number_bg} align={:center}>
  <Text text={"#{l.no}"} text_size={:sm} font_weight="bold" text_color={number_fg} />
</Box>)

    UI.list_tile(leading, l.title, "#{kind_label} · #{l.duration_min} 分钟",
      on_tap: tap,
      trailing: trailing
    )
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, :enroll}, socket) do
    result = Api.enroll(socket.assigns.course_id)

    socket =
      case result do
        {:ok, _} ->
          socket
          |> Mob.Socket.assign(:enrolled?, true)
          |> Mob.Socket.assign(:progress, Api.progress(socket.assigns.course_id))

        {:error, _} ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info({:tap, :continue}, socket) do
    course = socket.assigns.course

    next_lesson =
      Enum.find(course.lessons, fn l -> not Api.completed_lesson?(course.id, l.id) end) ||
        List.first(course.lessons)

    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.LearnScreen, %{
       course_id: course.id,
       lesson_id: next_lesson.id
     })}
  end

  def handle_info({:tap, {:lesson, lesson_id}}, socket) do
    if socket.assigns.enrolled? do
      {:noreply,
       Mob.Socket.push_screen(socket, TcmMobile.Screens.LearnScreen, %{
         course_id: socket.assigns.course_id,
         lesson_id: lesson_id
       })}
    else
      {:noreply, Mob.Socket.assign(socket, :hint, "请先选修本课程，再开始学习")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
