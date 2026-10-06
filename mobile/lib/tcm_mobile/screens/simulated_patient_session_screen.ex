defmodule TcmMobile.Screens.SimulatedPatientSessionScreen do
  @moduledoc """
  模拟患者会话 —— 问诊对话、辨证提交与结果展示。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{patient_id: patient_id}, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:patient_id, patient_id)
     |> Mob.Socket.assign(:session, Api.sp_session(patient_id))
     |> Mob.Socket.assign(:draft, "")
     |> Mob.Socket.assign(:dialectic, nil)
     |> Mob.Socket.assign(:submitting, false)}
  end

  @impl true
  def render(assigns) do
    session = assigns.session

    body =
      case session.status do
        :not_started -> render_intro(session)
        _ -> render_chat(session, assigns.submitting, assigns.dialectic, assigns.draft)
      end

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("模拟患者接诊")}
      {body}
    </Column>
    """
  end

  defp render_intro(session) do
    start_tap = {self(), :start}

    header_row =
      ~MOB"""
      <Row gap={:space_md} align={:center}>
        <Box
          width={52}
          height={52}
          corner_radius={:radius_pill}
          background={:secondary}
          align={:center}
        >
          <Text
            text={String.slice(session.name, 0, 1)}
            text_size={:xl}
            text_color={:on_secondary}
            font_weight="bold"
          />
        </Box>
        <Column gap={2} weight={1}>
          <Text text={session.name} text_size={:lg} font_weight="bold" text_color={:on_surface} />
          <Text
            text={"#{session.age}岁 · #{session.gender} · #{session.occupation}"}
            text_size={:sm}
            text_color={:muted}
          />
        </Column>
      </Row>
      """

    intro_card =
      UI.card([
        header_row,
        ~MOB(<Divider color={:border} />),
        ~MOB(<Text text="主诉" text_size={:xs} font_weight="medium" text_color={:muted} />),
        ~MOB(<Text
  text={session.chief_complaint}
  text_size={:base}
  font_weight="medium"
  text_color={:on_surface}
/>),
        ~MOB(<Button text="开始接诊" on_tap={start_tap} />)
      ])

    ~MOB"""
    <Scroll weight={1} padding={:space_lg} fill_width={true}>
      <Column gap={:space_md} fill_width={true}>
        {intro_card}
      </Column>
    </Scroll>
    """
  end

  defp render_chat(session, submitting, dialectic, draft) do
    send_tap = {self(), :send}
    draft_change = {self(), :draft}
    show_dialectic_tap = {self(), :show_dialectic}
    submit_dialectic_tap = {self(), :submit_dialectic}

    dialectic_section =
      cond do
        session.status == :completed ->
          report_tap = {self(), :report}
          grade = session.grade

          completed_header =
            ~MOB"""
            <Row gap={:space_sm} align={:center}>
              <Icon
                name={if grade.correct?, do: "check", else: "close"}
                text_size={22}
                text_color={if grade.correct?, do: :secondary, else: :error}
              />
              <Text
                text={if grade.correct?, do: "辨证正确，接诊完成", else: "辨证有偏差，请复习解析"}
                text_size={:base}
                font_weight="medium"
                text_color={:on_surface}
              />
            </Row>
            """

          completed_card =
            UI.card([
              completed_header,
              ~MOB(<Text text={"辨证结果：#{grade.syndrome}"} text_size={:base} text_color={:on_surface} />),
              ~MOB(<Text text={grade.reasoning} text_size={:sm} text_color={:muted} />),
              ~MOB(<Button text="查看临床推理报告" on_tap={report_tap} />)
            ])

          completed_card

        submitting ->
          options =
            Enum.with_index(session.dialectic_options, fn opt, i ->
              tap = {self(), {:dialectic, i}}
              selected = dialectic == i
              bg = if selected, do: :primary, else: :surface
              fg = if selected, do: :on_primary, else: :on_surface

              ~MOB(<Box
  background={bg}
  corner_radius={:radius_md}
  padding={:space_md}
  fill_width={true}
  on_tap={tap}
>
  <Text text={opt} text_size={:base} text_color={fg} />
</Box>)
            end)

          UI.card([
            ~MOB(<Text text="请选择最符合的辨证结论" text_size={:base} font_weight="medium" text_color={:on_surface} />),
            ~MOB(<Column gap={:space_sm}>
  {options}
</Column>),
            ~MOB(<Button text="提交辨证" on_tap={submit_dialectic_tap} disabled={dialectic == nil} />)
          ])

        true ->
          ~MOB(<Button text="提交辨证论治" on_tap={show_dialectic_tap} background={:surface} text_color={:primary} />)
      end

    messages = session.messages || []

    patient_card =
      UI.card([
        ~MOB(<Text
  text={"患者：#{session.name}（#{session.age}岁 #{session.gender}）"}
  text_size={:base}
  font_weight="medium"
  text_color={:on_surface}
/>),
        ~MOB(<Text text={"主诉：#{session.chief_complaint}"} text_size={:sm} text_color={:muted} />)
      ])

    ~MOB"""
    <Column fill_height={true}>
      <Scroll weight={1} padding={:space_md} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {patient_card}
          <Column gap={:space_sm}>
            {Enum.map(messages, fn m -> sp_bubble(%{m: m}) end)}
          </Column>
          {dialectic_section}
        </Column>
      </Scroll>
      <Row
        gap={:space_sm}
        padding={:space_md}
        background={:surface}
        border_color={:border}
        border_top_width={1}
        align={:center}
      >
        <TextField value={draft} placeholder="向患者询问病情…" on_change={draft_change} weight={1} />
        <Box
          on_tap={send_tap}
          fill_width={false}
          background={:primary}
          corner_radius={:radius_pill}
          padding={:space_md}
        >
          <Icon name="forward" text_size={18} text_color={:on_primary} />
        </Box>
      </Row>
    </Column>
    """
  end

  defp sp_bubble(assigns) do
    {bg, fg, align, label} =
      case assigns.m.role do
        :patient -> {:surface_raised, :on_surface, :leading, "患者"}
        :student -> {:primary, :on_primary, :trailing, "我"}
        :doctor -> {:secondary, :on_secondary, :leading, assigns.m.speaker || "会诊"}
      end

    ~MOB"""
    <Box fill_width={true} align={align}>
      <Column gap={2}>
        <Text text={label} text_size={:xs} text_color={:muted} padding_bottom={2} />
        <Box background={bg} corner_radius={:radius_lg} padding={:space_md} fill_width={false}>
          <Text text={assigns.m.text} text_size={:base} text_color={fg} />
        </Box>
        <Text text={assigns.m.time} text_size={:xs} text_color={:muted} padding_top={2} />
      </Column>
    </Box>
    """
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, :start}, socket) do
    session = Api.start_sp(socket.assigns.patient_id)
    {:noreply, Mob.Socket.assign(socket, :session, session)}
  end

  def handle_info({:change, :draft, value}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :draft, value)}

  def handle_info({:tap, :send}, socket) do
    text = String.trim(socket.assigns.draft)

    if text == "" do
      {:noreply, socket}
    else
      session = Api.send_sp(socket.assigns.patient_id, text)
      {:noreply, socket |> Mob.Socket.assign(:session, session) |> Mob.Socket.assign(:draft, "")}
    end
  end

  def handle_info({:tap, :show_dialectic}, socket) do
    {:noreply, Mob.Socket.assign(socket, :submitting, true)}
  end

  def handle_info({:tap, {:dialectic, index}}, socket) do
    {:noreply, Mob.Socket.assign(socket, :dialectic, index)}
  end

  def handle_info({:tap, :submit_dialectic}, socket) do
    session = Api.submit_sp(socket.assigns.patient_id, socket.assigns.dialectic)

    {:noreply,
     socket |> Mob.Socket.assign(:session, session) |> Mob.Socket.assign(:submitting, false)}
  end

  def handle_info({:tap, :report}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.ReasoningReportScreen, %{
       patient_id: socket.assigns.patient_id
     })}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
