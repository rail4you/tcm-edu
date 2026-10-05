defmodule TcmMobile.Screens.ExamsScreen do
  @moduledoc "测验列表 —— 查看测验状态、成绩与入口。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    exams =
      Enum.map(Api.list_exams(), fn exam ->
        Map.merge(exam, %{attempt: Api.exam_attempt(exam.id)})
      end)

    {:ok, Mob.Socket.assign(socket, :exams, exams)}
  end

  @impl true
  def render(assigns) do
    rows = Enum.map(assigns.exams, &exam_row/1)

    hint_card =
      UI.card([
        ~MOB(<Text text="完成阶段测验，检验阶段性学习成果；测验错题将自动收录到错题本。" text_size={:sm} text_color={:muted} />)
      ])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("测验考试")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {hint_card}
          {rows}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp exam_row(exam) do
    status = exam_status(exam)
    tap = {self(), {:exam, exam.id}}
    tint = status_tint(status.color)

    subtitle = "#{exam.duration_min} 分钟 · #{length(exam.questions)} 题 · 满分 #{exam.total_points}"

    trailing =
      ~MOB"""
      <Box
        background={status.color}
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

    cond do
      attempt.submitted and attempt.score >= exam.pass_score ->
        %{label: "已通过 · #{attempt.score} 分", color: :secondary}

      attempt.submitted ->
        %{label: "未通过 · #{attempt.score} 分", color: :error}

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
