defmodule TcmMobile.Screens.ReasoningReportScreen do
  @moduledoc "临床推理报告 —— 模拟患者接诊后的辨证推理结构化报告。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{patient_id: patient_id}, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :session, Api.sp_session(patient_id))}
  end

  @impl true
  def render(assigns) do
    session = assigns.session
    grade = session.grade || %{}

    report_tap = {self(), :back}

    header_row =
      ~MOB"""
      <Row gap={:space_md} align={:center}>
        <Box
          width={48}
          height={48}
          corner_radius={:radius_pill}
          background={:secondary}
          align={:center}
        >
          <Text
            text={String.slice(session.name, 0, 1)}
            text_size={:lg}
            text_color={:on_secondary}
            font_weight="bold"
          />
        </Box>
        <Column gap={2} weight={1}>
          <Text text={session.name} text_size={:lg} font_weight="bold" text_color={:on_surface} />
          <Text text={"#{session.age}岁 · #{session.gender}"} text_size={:sm} text_color={:muted} />
        </Column>
        <Box
          background={if grade.correct?, do: :secondary, else: :error}
          fill_width={false}
          corner_radius={:radius_pill}
          padding_top={4}
          padding_bottom={4}
          padding_left={:space_sm}
          padding_right={:space_sm}
        >
          <Text
            text={if grade.correct?, do: "辨证正确", else: "需加强"}
            text_size={:xs}
            text_color={if grade.correct?, do: :on_secondary, else: :on_error}
          />
        </Box>
      </Row>
      """

    header_card = UI.card([header_row])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("临床推理报告")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {header_card}
          {report_section("主诉", session.chief_complaint)}
          {report_section("辨证结论", grade[:syndrome])}
          {report_section("推理过程", grade[:reasoning])}
          {report_section("治疗路径", Enum.join(grade[:pathway] || [], "\n"))}
          {report_section("反思提示", "接诊时注意四诊合参：望神色、听声音、问情志、切脉象。采集完整病史后再下结论，避免先入为主。")}
          <Button text="返回模拟患者" on_tap={report_tap} />
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp report_section(title, body) do
    UI.card([
      ~MOB(<Text text={title} text_size={:xs} font_weight="medium" text_color={:primary} />),
      ~MOB(<Text text={body || "—"} text_size={:base} text_color={:on_surface} />)
    ])
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}
end
