defmodule TcmMobile.Screens.ExamTakeScreen do
  @moduledoc """
  测验 / 考试作答 —— 逐题作答、交卷、结果展示（含逐题解析）。

  * 单选题：测验当场自动判分
  * 填空 / 问答题：测验只展示参考答案，不计分
  * 考试卷：整卷提交后待人工评阅，不产生自动成绩
  * 所有题目作答完毕才允许交卷，否则定位到第一道未作答题
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}
  alias TcmMobile.Data.Questions

  @impl true
  def mount(%{exam_id: exam_id}, _session, socket) do
    exam = Api.get_exam(exam_id)
    attempt = Api.exam_attempt(exam_id)

    {:ok,
     socket
     |> Mob.Socket.assign(:exam, exam)
     |> Mob.Socket.assign(:attempt, attempt)
     |> Mob.Socket.assign(:index, first_unanswered(exam, attempt))
     |> Mob.Socket.assign(:result, Api.exam_result(exam_id))
     |> Mob.Socket.assign(:notice, nil)}
  end

  defp first_unanswered(exam, attempt) do
    exam.questions
    |> Enum.find_index(fn q -> not Questions.answered?(q, Map.get(attempt.answers, q.id)) end)
    |> case do
      nil -> 0
      i -> i
    end
  end

  @impl true
  def render(assigns) do
    exam = assigns.exam

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {if assigns.result,
        do: render_result(assigns.result, exam),
        else: render_taking(assigns)}
    </Column>
    """
  end

  defp render_taking(assigns) do
    prev_tap = {self(), :prev}
    next_tap = {self(), :next}
    submit_tap = {self(), :submit_confirm}

    exam = assigns.exam
    question = Enum.at(exam.questions, assigns.index)
    attempt = assigns.attempt
    qnum = assigns.index + 1

    total = length(exam.questions)
    progress = "#{qnum} / #{total}"

    body =
      case Questions.type(question) do
        :single -> option_rows(question, attempt)
        :fill -> text_input(question, attempt, exam, 1, "在此填写答案…")
        :essay -> text_input(question, attempt, exam, 5, "在此作答…")
      end

    # 底部操作条固定在 Scroll 之外，两个按钮各 weight=1 平分宽度 —— 少了这个
    # 权重，Row 里第一个按钮会吃掉整行宽度，把「下一题」挤出屏幕（第 2 题起就
    # 只剩「上一题」，无法继续作答）。第一题没有上一题，用等宽占位符保持主按钮在右。
    prev_button =
      if qnum > 1 do
        ~MOB(<Button
  text="上一题"
  weight={1}
  on_tap={prev_tap}
  background={:surface_raised}
  text_color={:on_surface}
/>)
      else
        ~MOB(<Spacer weight={1} />)
      end

    action_button =
      if qnum < total do
        ~MOB(<Button text="下一题" weight={1} on_tap={next_tap} background={:primary} text_color={:on_primary} />)
      else
        ~MOB(<Button text="交卷" weight={1} on_tap={submit_tap} background={:primary} text_color={:on_primary} />)
      end

    notice_node =
      if assigns.notice do
        ~MOB(<Text
  text={assigns.notice}
  fill_width={true}
  text_size={:sm}
  text_color={:error}
  padding={:space_md}
/>)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    # Box 是 Compose Box（子节点堆叠），多行内容必须再包一层 Column，否则
    # 题干上方的「第 N 题」会和题干重叠被盖住。
    question_card =
      UI.card(
        [
          ~MOB(<Text text={"第 #{qnum} 题，共 #{total} 题"} text_size={:xs} text_color={:muted} />),
          ~MOB(<Text text={question.text} text_size={:lg} font_weight="bold" text_color={:on_surface} />)
        ],
        padding: :space_lg
      )

    ~MOB"""
    <Column fill_height={true}>
      {UI.detail_header(header(exam, "作答"))}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Row gap={:space_sm} align={:center}>
            <Text
              text={exam.title}
              text_size={:sm}
              font_weight="medium"
              text_color={:muted}
              weight={1}
              max_lines={1}
            />
            {UI.chip(progress)}
          </Row>
          {question_card}
          {body}
        </Column>
      </Scroll>
      <Column fill_width={true}>
        <Box fill_width={true} height={1} background={:border} />
        {notice_node}
        <Row
          gap={:space_sm}
          fill_width={true}
          padding={:space_md}
          padding_bottom={:space_lg}
          background={:surface}
        >
          {prev_button}
          {action_button}
        </Row>
      </Column>
    </Column>
    """
  end

  defp option_rows(question, attempt) do
    selected = Map.get(attempt.answers, question.id)

    question.options
    |> Enum.with_index()
    |> Enum.map(fn {opt, i} -> option_row(question, opt, i, selected == i) end)
  end

  defp option_row(question, opt, i, selected?) do
    tap = {self(), {:answer, question.id, i}}
    bg = if selected?, do: :primary, else: :surface
    fg = if selected?, do: :on_primary, else: :on_surface
    badge_bg = if selected?, do: :on_primary, else: :background
    badge_fg = if selected?, do: :primary, else: :muted

    ~MOB"""
    <Box
      background={bg}
      corner_radius={:radius_md}
      padding={:space_md}
      fill_width={true}
      on_tap={tap}
      border_color={:border}
      border_width={if selected?, do: 0, else: 1}
    >
      <Row gap={:space_sm} align={:center} fill_width={true}>
        <Box
          background={badge_bg}
          corner_radius={:radius_pill}
          width={28}
          height={28}
          align={:center}
        >
          <Text text={option_label(i)} text_size={:sm} font_weight="medium" text_color={badge_fg} />
        </Box>
        <Text text={opt} text_size={:base} text_color={fg} weight={1} />
      </Row>
    </Box>
    """
  end

  defp option_label(i), do: <<?A + i>>

  defp text_input(question, attempt, exam, lines, placeholder) do
    value = answer_text(question, attempt)
    change = {self(), {:answer_text, question.id}}

    hint =
      if exam.mode == :exam do
        "考试卷提交后由阅卷老师人工评阅，不计自动分。"
      else
        "填空、问答题不计分，交卷后可查看参考答案。"
      end

    ~MOB"""
    <Column gap={:space_sm} fill_width={true}>
      <TextField
        value={value}
        placeholder={placeholder}
        on_change={change}
        fill_width={true}
        lines={lines}
        max_length={2000}
      />
      <Text text={hint} text_size={:xs} text_color={:muted} />
    </Column>
    """
  end

  defp answer_text(question, attempt) do
    case Map.get(attempt.answers, question.id) do
      text when is_binary(text) -> text
      _ -> ""
    end
  end

  defp header(exam, suffix) do
    if exam.mode == :exam, do: "考试#{suffix}", else: "测验#{suffix}"
  end

  defp render_result(result, exam) do
    back_tap = {self(), :done}

    review = Enum.map(exam.questions, &review_item(&1, result.attempt.answers, result))

    section = if result.graded?, do: "逐题解析", else: "逐题回顾（含参考答案）"

    ~MOB"""
    <Column fill_height={true}>
      {UI.detail_header(header(exam, "结果"))}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          <Box
            background={:surface}
            corner_radius={:radius_lg}
            padding={:space_lg}
            fill_width={true}
            align={:center}
          >
            {summary(result, exam)}
          </Box>
          {UI.section_header(section)}
          {review}
          <Button text="完成" on_tap={back_tap} />
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp summary(result, exam) do
    title = ~MOB(<Text
  text={exam.title}
  fill_width={true}
  text_align="center"
  text_size={:base}
  text_color={:muted}
/>)

    if result.graded? do
      ~MOB"""
      <Column gap={:space_sm} fill_width={true}>
        {title}
        <Text
          text={"#{result.score}"}
          fill_width={true}
          text_align="center"
          text_size={:"5xl"}
          font_weight="bold"
          text_color={if(result.pass?, do: :secondary, else: :error)}
        />
        <Text
          text={"答对 #{result.correct} / #{result.choice_total} 道选择题"}
          fill_width={true}
          text_align="center"
          text_size={:base}
          text_color={:on_surface}
        />
        <Text
          text="填空、问答题不计分，可在下方查看参考答案。"
          fill_width={true}
          text_align="center"
          text_size={:sm}
          text_color={:muted}
        />
        <Text
          text={if(result.pass?, do: "测验通过，继续加油！", else: "未达及格线，请复习错题")}
          fill_width={true}
          text_align="center"
          text_size={:sm}
          text_color={:muted}
        />
      </Column>
      """
    else
      ~MOB"""
      <Column gap={:space_sm} fill_width={true}>
        {title}
        <Text
          text="已交卷"
          fill_width={true}
          text_align="center"
          text_size={:"5xl"}
          font_weight="bold"
          text_color={:primary}
        />
        <Text
          text="待人工评阅"
          fill_width={true}
          text_align="center"
          text_size={:lg}
          font_weight="medium"
          text_color={:on_surface}
        />
        <Text
          text="全卷（含选择、填空、问答）由阅卷老师人工评阅，成绩公布后可在「我的考试记录」查看。"
          fill_width={true}
          text_align="center"
          text_size={:sm}
          text_color={:muted}
        />
      </Column>
      """
    end
  end

  defp review_item(q, answers, result) do
    given = Map.get(answers, q.id)
    graded? = result.graded? and Questions.type(q) == :single
    correct? = graded? and given == q.answer

    leading =
      if graded? do
        %{
          type: :icon,
          props: %{
            name: if(correct?, do: "check", else: "close"),
            text_size: 18,
            text_color: if(correct?, do: :secondary, else: :error)
          },
          children: []
        }
      else
        UI.chip(type_label(q))
      end

    answer_color = if graded? and not correct?, do: :error, else: :muted

    %{
      type: :column,
      props: %{gap: 4, fill_width: true},
      children: [
        %{
          type: :row,
          props: %{gap: :space_sm, align: :center, fill_width: true},
          children: [
            leading,
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
            text: "你的答案：#{answer_display(q, given)}",
            text_size: :sm,
            text_color: answer_color
          },
          children: []
        },
        %{
          type: :text,
          props: %{
            text: "#{if(graded?, do: "正确答案", else: "参考答案")}：#{reference_display(q)}",
            text_size: :sm,
            text_color: :secondary
          },
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

  defp type_label(q) do
    case Questions.type(q) do
      :single -> "单选"
      :fill -> "填空"
      :essay -> "问答"
    end
  end

  defp answer_display(_q, nil), do: "未作答"

  defp answer_display(q, given) when is_integer(given),
    do: Enum.at(q.options, given) || "未作答"

  defp answer_display(_q, given) when is_binary(given) do
    if String.trim(given) == "", do: "未作答", else: given
  end

  defp reference_display(q) do
    case q.answer do
      idx when is_integer(idx) -> Enum.at(q.options, idx)
      text -> text
    end
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, :done}, socket) do
    {:noreply, Mob.Socket.pop_to(socket, TcmMobile.Screens.ExamsScreen)}
  end

  def handle_info({:tap, {:answer, question_id, index}}, socket) do
    Api.save_answer(socket.assigns.exam.id, question_id, index)

    {:noreply,
     socket
     |> Mob.Socket.assign(:attempt, Api.exam_attempt(socket.assigns.exam.id))
     |> Mob.Socket.assign(:notice, nil)}
  end

  def handle_info({:change, {:answer_text, question_id}, value}, socket) do
    Api.save_answer(socket.assigns.exam.id, question_id, value)

    {:noreply,
     socket
     |> Mob.Socket.assign(:attempt, Api.exam_attempt(socket.assigns.exam.id))
     |> Mob.Socket.assign(:notice, nil)}
  end

  def handle_info({:tap, :next}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.update(:index, &min(&1 + 1, length(socket.assigns.exam.questions) - 1))
     |> Mob.Socket.assign(:notice, nil)}
  end

  def handle_info({:tap, :prev}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.update(:index, &max(&1 - 1, 0))
     |> Mob.Socket.assign(:notice, nil)}
  end

  def handle_info({:tap, :submit_confirm}, socket) do
    exam = socket.assigns.exam
    attempt = socket.assigns.attempt

    case missing(exam, attempt) do
      nil ->
        case Api.submit_exam(exam.id) do
          {:error, {:unanswered, count, idx}} ->
            {:noreply, located(socket, count, idx)}

          result ->
            {:noreply,
             socket
             |> Mob.Socket.assign(:result, result)
             |> Mob.Socket.assign(:attempt, result.attempt)
             |> Mob.Socket.assign(:notice, nil)}
        end

      {count, idx} ->
        {:noreply, located(socket, count, idx)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp missing(exam, attempt) do
    missing =
      exam.questions
      |> Enum.with_index()
      |> Enum.reject(fn {question, _idx} ->
        Questions.answered?(question, Map.get(attempt.answers, question.id))
      end)
      |> Enum.map(fn {_question, idx} -> idx end)

    case missing do
      [] -> nil
      [idx | _] -> {length(missing), idx}
    end
  end

  defp located(socket, count, idx) do
    socket
    |> Mob.Socket.assign(:index, idx)
    |> Mob.Socket.assign(:notice, "还有 #{count} 题未作答，已定位到第 #{idx + 1} 题")
  end
end
