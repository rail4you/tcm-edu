defmodule TcmMobile.Screens.ExamsScreen do
  @moduledoc "测验列表 —— 查看测验状态、成绩与入口。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :records, Api.my_exam_records())}
  end

  @impl true
  def render(assigns) do
    # 作答页交卷后 pop 回本页不会重新 mount，所以考卷与作答状态每次渲染重取。
    exams = load_exams()

    rows = Enum.map(exams, &exam_row/1)
    record_rows = Enum.map(assigns.records, &record_row/1)

    hint_card =
      UI.card([
        ~MOB(<Text
  text="测验：选择题自动判分，填空、问答题只看参考答案，错题自动收录错题本；考试：全卷提交后由老师人工评阅。"
  text_size={:sm}
  text_color={:muted}
/>)
      ])

    records_header =
      if assigns.records == [] do
        %{type: :spacer, props: %{}, children: []}
      else
        UI.section_header("我的考试记录")
      end

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("测验考试")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {hint_card}
          {rows}
          {records_header}
          {record_rows}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp record_row(record) do
    tint = if record.status == "graded", do: :secondary, else: :primary

    subtitle =
      [status_label(record.status), score_label(record.score), date_label(record.assigned_at)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    UI.list_tile(UI.glyph_tile("考", tint, 44), record.exam_name, subtitle, trailing: nil)
  end

  defp status_label("graded"), do: "已批阅"
  defp status_label("submitted"), do: "已提交"
  defp status_label("in_progress"), do: "作答中"
  defp status_label(_), do: "待作答"

  defp score_label(nil), do: nil

  defp score_label(score) when is_float(score) do
    if score == trunc(score), do: "#{trunc(score)} 分", else: "#{score} 分"
  end

  defp score_label(score), do: "#{score} 分"

  defp date_label(nil), do: nil
  defp date_label(iso) when is_binary(iso), do: String.slice(iso, 0, 10)

  defp load_exams do
    Enum.map(Api.list_exams(), fn exam ->
      Map.merge(exam, %{attempt: Api.exam_attempt(exam.id)})
    end)
  end

  defp exam_row(exam) do
    status = exam_status(exam)
    tap = {self(), {:exam, exam.id}}
    tint = status_tint(status.color)

    mode = if exam.mode == :exam, do: "考试", else: "测验"

    subtitle =
      "#{mode} · #{exam.duration_min} 分钟 · #{length(exam.questions)} 题 · 满分 #{exam.total_points}"

    trailing =
      ~MOB"""
      <Box
        background={status.color}
        fill_width={false}
        corner_radius={:radius_pill}
        padding_top={4}
        padding_bottom={4}
        padding_left={:space_sm}
        padding_right={:space_sm}
      >
        <Text
          text={status.label}
          text_size={:xs}
          text_color={status_text_color(status.color)}
          font_weight="medium"
        />
      </Box>
      """

    UI.list_tile(UI.glyph_tile("测", tint, 44), exam.title, subtitle,
      on_tap: tap,
      trailing: trailing
    )
  end

  defp status_tint(:secondary), do: :secondary
  defp status_tint(:error), do: :error
  defp status_tint(:primary), do: :primary
  defp status_tint(_), do: :gold

  defp status_text_color(:secondary), do: :on_secondary
  defp status_text_color(:primary), do: :on_primary
  defp status_text_color(:error), do: :on_error
  defp status_text_color(_), do: :on_surface

  defp exam_status(exam) do
    attempt = exam.attempt
    graded? = Map.get(attempt, :graded?)
    score = Map.get(attempt, :score)

    cond do
      attempt.submitted and graded? == false ->
        %{label: "待评阅", color: :primary}

      attempt.submitted and is_integer(score) and score >= exam.pass_score ->
        %{label: "已通过 · #{score} 分", color: :secondary}

      attempt.submitted ->
        %{label: "未通过 · #{score} 分", color: :error}

      map_size(attempt.answers) > 0 ->
        %{label: "继续作答", color: :primary}

      true ->
        %{label: "未开始", color: :gold}
    end
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:exam, exam_id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.ExamTakeScreen, %{exam_id: exam_id})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
