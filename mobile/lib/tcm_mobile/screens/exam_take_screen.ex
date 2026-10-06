defmodule TcmMobile.Screens.ExamTakeScreen do
  @moduledoc """
  测验作答 —— 逐题作答、提交评分、结果展示（含逐题解析）。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{exam_id: exam_id}, _session, socket) do
    exam = Api.get_exam(exam_id)
    attempt = Api.exam_attempt(exam_id)
    index = first_unanswered(exam, attempt)

    {:ok,
     socket
     |> Mob.Socket.assign(:exam, exam)
     |> Mob.Socket.assign(:attempt, attempt)
     |> Mob.Socket.assign(:index, index)
     |> Mob.Socket.assign(:result, nil)
     |> Mob.Socket.assign(:confirming, false)}
  end

  defp first_unanswered(exam, attempt) do
    exam.questions
    |> Enum.find_index(fn q -> not Map.has_key?(attempt.answers, q.id) end)
    |> case do
      nil -> 0
      i -> i
    end
  end

  @impl true
  def render(assigns) do
    exam = assigns.exam
    question = Enum.at(exam.questions, assigns.index)
    qnum = assigns.index + 1

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {if assigns.result, do: render_result(assigns.result, exam), else: render_taking(exam, question, qnum, assigns.attempt)}
    </Column>
    """
  end

  defp render_taking(exam, question, qnum, attempt) do
    prev_tap = {self(), :prev}
    next_tap = {self(), :next}
    submit_tap = {self(), :submit_confirm}

    selected = Map.get(attempt.answers, question.id)

    options =
      Enum.with_index(question.options, fn opt, i ->
        tap = {self(), {:answer, question.id, i}}
        is_selected = selected == i
        bg = if is_selected, do: :primary, else: :surface
        fg = if is_selected, do: :on_primary, else: :on_surface

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

    progress = "#{qnum} / #{length(exam.questions)}"

    buttons =
      cond do
        qnum < length(exam.questions) ->
          ~MOB(<Button text="下一题" on_tap={next_tap} />)

        true ->
          ~MOB(<Button text="交卷" on_tap={submit_tap} />)
      end

    prev_button =
      if qnum > 1 do
        ~MOB(<Button text="上一题" on_tap={prev_tap} background={:surface} text_color={:on_surface} />)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Column fill_height={true}>
      {UI.detail_header("测验作答")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Row gap={:space_sm} align={:center}>
            <Text
              text={exam.title}
              text_size={:sm}
              font_weight="medium"
              text_color={:on_surface}
              weight={1}
              max_lines={1}
            />
            {UI.chip(progress)}
          </Row>
          <Box background={:surface} corner_radius={:radius_lg} padding={:space_md} fill_width={true}>
            <Text text={"第 #{qnum} 题"} text_size={:xs} text_color={:muted} />
            <Spacer size={6} />
            <Text
              text={question.text}
              text_size={:base}
              font_weight="medium"
              text_color={:on_surface}
            />
          </Box>
          <Column gap={:space_sm}>
            {options}
          </Column>
          <Row gap={:space_sm}>
            {prev_button}
            {buttons}
          </Row>
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp render_result(result, exam) do
    back_tap = {self(), :done}

    review = Enum.map(exam.questions, fn q -> review_item(q, result.attempt.answers) end)

    score_color = if result.pass?, do: :secondary, else: :error

    ~MOB"""
    <Column fill_height={true}>
      {UI.detail_header("测验结果")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Box
            background={:surface}
            corner_radius={:radius_lg}
            padding={:space_lg}
            fill_width={true}
            align={:center}
          >
            <Column gap={:space_sm} fill_width={true}>
              <Text
                text={exam.title}
                fill_width={true}
                text_align="center"
                text_size={:base}
                text_color={:muted}
              />
              <Text
                text={"#{result.score}"}
                fill_width={true}
                text_align="center"
                text_size={:"5xl"}
                font_weight="bold"
                text_color={score_color}
              />
              <Text
                text={"答对 #{result.correct} / #{result.total} 题"}
                fill_width={true}
                text_align="center"
                text_size={:base}
                text_color={:on_surface}
              />
              <Text
                text={
                  if result.pass?, do: "测验通过，继续加油！", else: "未达及格线，请复习错题"
                }
                fill_width={true}
                text_align="center"
                text_size={:sm}
                text_color={:muted}
              />
            </Column>
          </Box>
          {UI.section_header("逐题解析")}
          {review}
          <Button text="完成" on_tap={back_tap} />
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp review_item(q, answers) do
    given = Map.get(answers, q.id)
    correct? = given == q.answer

    given_text = if given, do: Enum.at(q.options, given), else: "未作答"
    correct_text = Enum.at(q.options, q.answer)

    %{
      type: :column,
      props: %{gap: 4, fill_width: true},
      children: [
        %{
          type: :row,
          props: %{gap: :space_sm, align: :center},
          children: [
            %{
              type: :icon,
              props: %{
                name: if(correct?, do: "check", else: "close"),
                text_size: 18,
                text_color: if(correct?, do: :secondary, else: :error)
              },
              children: []
            },
            %{
              type: :text,
              props: %{text: q.text, text_size: :base, text_color: :on_surface, weight: 1},
              children: []
            }
          ]
        },
        %{
          type: :text,
          props: %{
            text: "你的答案：#{given_text}",
            text_size: :sm,
            text_color: if(correct?, do: :muted, else: :error)
          },
          children: []
        },
        %{
          type: :text,
          props: %{text: "正确答案：#{correct_text}", text_size: :sm, text_color: :secondary},
          children: []
        },
        %{
          type: :text,
          props: %{text: q.explanation, text_size: :xs, text_color: :muted},
          children: []
        },
        %{type: :divider, props: %{color: :border}, children: []}
      ]
    }
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, :done}, socket) do
    {:noreply, Mob.Socket.pop_to(socket, TcmMobile.Screens.ExamsScreen)}
  end

  def handle_info({:tap, {:answer, question_id, index}}, socket) do
    Api.save_answer(socket.assigns.exam.id, question_id, index)
    {:noreply, Mob.Socket.assign(socket, :attempt, Api.exam_attempt(socket.assigns.exam.id))}
  end

  def handle_info({:tap, :next}, socket) do
    {:noreply,
     Mob.Socket.update(socket, :index, &min(&1 + 1, length(socket.assigns.exam.questions) - 1))}
  end

  def handle_info({:tap, :prev}, socket) do
    {:noreply, Mob.Socket.update(socket, :index, &max(&1 - 1, 0))}
  end

  def handle_info({:tap, :submit_confirm}, socket) do
    result = Api.submit_exam(socket.assigns.exam.id)

    {:noreply,
     socket |> Mob.Socket.assign(:result, result) |> Mob.Socket.assign(:attempt, result.attempt)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
