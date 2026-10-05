defmodule TcmMobile.Screens.LearnScreen do
  @moduledoc """
  课时学习 —— 正文 + 可选随堂测验 + 完成标记与下一课时。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{course_id: course_id, lesson_id: lesson_id}, _session, socket) do
    lesson = Api.lesson(course_id, lesson_id)
    content = Api.lesson_content(lesson_id)
    quiz = Api.lesson_quiz(lesson_id)
    course = Api.get_course(course_id)

    {:ok,
     socket
     |> Mob.Socket.assign(:course_id, course_id)
     |> Mob.Socket.assign(:lesson_id, lesson_id)
     |> Mob.Socket.assign(:lesson, lesson)
     |> Mob.Socket.assign(:content, content)
     |> Mob.Socket.assign(:quiz, quiz)
     |> Mob.Socket.assign(:course, course)
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.assign(:feedback, nil)
     |> Mob.Socket.assign(:completed?, Api.completed_lesson?(course_id, lesson_id))}
  end

  @impl true
  def render(assigns) do
    lesson = assigns.lesson
    quiz = assigns.quiz
    selected = assigns.selected
    feedback = assigns.feedback
    completed? = assigns.completed?
    course = assigns.course
    lesson_id = assigns.lesson_id
    content = assigns.content
    complete_tap = {self(), :complete}
    next_tap = {self(), :next}
    back_tap = {self(), :back}

    kind_label = %{text: "图文课时", video: "视频课时", quiz: "随堂测验"}

    quiz_section =
      if quiz do
        options =
          Enum.with_index(quiz.options, fn opt, i ->
            opt_selected = selected == i
            tap = {self(), {:answer, i}}

            bg =
              cond do
                feedback && i == quiz.answer -> :secondary
                feedback && i == selected -> :error
                opt_selected -> :primary
                true -> :surface
              end

            fg =
              cond do
                feedback && (i == quiz.answer or i == selected) -> :on_secondary
                opt_selected -> :on_primary
                true -> :on_surface
              end

            ~MOB(<Box
  background={bg}
  corner_radius={:radius_md}
  padding={:space_md}
  fill_width={true}
  on_tap={tap}
>
  <Text text={"#{opt}"} text_size={:base} text_color={fg} />
</Box>)
          end)

        feedback_node =
          if feedback do
            ~MOB(<Box
  background={if feedback[:correct?], do: :secondary, else: :error}
  corner_radius={:radius_md}
  padding={:space_md}
  fill_width={true}
>
  <Text
    text={feedback[:text]}
    text_size={:sm}
    text_color={if feedback[:correct?], do: :on_secondary, else: :on_error}
  />
</Box>)
          else
            %{type: :spacer, props: %{}, children: []}
          end

        ~MOB"""
        <Column
          gap={:space_md}
          fill_width={true}
          padding={:space_md}
          background={:surface}
          corner_radius={:radius_lg}
        >
          {UI.section_label("随堂测验")}
          <Text text={quiz.text} text_size={:base} font_weight="medium" text_color={:on_surface} />
          <Column gap={:space_sm}>
            {options}
          </Column>
          {feedback_node}
        </Column>
        """
      else
        %{type: :spacer, props: %{}, children: []}
      end

    complete_button =
      if completed? do
        ~MOB(<Button text="已完成" on_tap={complete_tap} background={:secondary} disabled={true} />)
      else
        ~MOB(<Button text="标记完成" on_tap={complete_tap} />)
      end

    next_button =
      if next_lesson(course, lesson_id) do
        ~MOB(<Button text="下一课时" on_tap={next_tap} background={:surface} text_color={:on_surface} />)
      else
        ~MOB(<Button text="返回课程" on_tap={back_tap} background={:surface} text_color={:on_surface} />)
      end

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header(lesson.title)}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Row gap={:space_sm} align={:center}>
            {UI.chip("课时 #{lesson.no}")}
            {UI.chip("#{Map.fetch!(kind_label, lesson.kind)} · #{lesson.duration_min} 分钟")}
          </Row>
          <Column gap={:space_sm}>
            {Enum.map(content, fn p ->
              ~MOB(<Text text={p} text_size={:base} text_color={:on_surface} />)
            end)}
          </Column>
          {quiz_section}
          {complete_button}
          {next_button}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp next_lesson(course, lesson_id) do
    idx = Enum.find_index(course.lessons, &(&1.id == lesson_id))

    case idx do
      nil -> nil
      i -> Enum.at(course.lessons, i + 1)
    end
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:answer, index}}, socket) do
    quiz = socket.assigns.quiz
    correct? = index == quiz.answer
    feedback = %{correct?: correct?, text: TcmMobile.Data.Ai.quiz_feedback(quiz, index)}

    {:noreply,
     socket |> Mob.Socket.assign(:selected, index) |> Mob.Socket.assign(:feedback, feedback)}
  end

  def handle_info({:tap, :complete}, socket) do
    Api.complete_lesson(socket.assigns.course_id, socket.assigns.lesson_id)
    {:noreply, Mob.Socket.assign(socket, :completed?, true)}
  end

  def handle_info({:tap, :next}, socket) do
    Api.complete_lesson(socket.assigns.course_id, socket.assigns.lesson_id)

    case next_lesson(socket.assigns.course, socket.assigns.lesson_id) do
      nil ->
        {:noreply, Mob.Socket.pop_screen(socket)}

      next ->
        {:noreply,
         Mob.Socket.push_screen(socket, TcmMobile.Screens.LearnScreen, %{
           course_id: socket.assigns.course_id,
           lesson_id: next.id
         })}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
