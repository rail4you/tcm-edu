defmodule TcmMobile.Screens.SimulatedPatientScreen do
  @moduledoc "模拟患者列表 —— 标准化病人任务。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :patients, Api.list_sp_patients())}
  end

  @impl true
  def render(assigns) do
    rows = Enum.map(assigns.patients, &patient_row/1)

    hint_card =
      UI.card([
        ~MOB(<Text text="通过标准化病人训练四诊采集与辨证论治能力，接诊后可查看临床推理报告。" text_size={:sm} text_color={:muted} />)
      ])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("模拟患者")}
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

  defp patient_row(p) do
    status = sp_status(p)
    tap = {self(), {:patient, p.id}}

    trailing =
      ~MOB"""
      <Box
        background={status.bg}
        corner_radius={:radius_pill}
        padding_top={4}
        padding_bottom={4}
        padding_left={:space_sm}
        padding_right={:space_sm}
      >
        <Text text={status.label} text_size={:xs} text_color={status.fg} font_weight="medium" />
      </Box>
      """

    leading = UI.glyph_tile(String.slice(p.name, 0, 1), :primary, 44)
    subtitle = "#{p.age}岁 · #{p.gender} · 主诉：#{p.chief_complaint}"

    UI.list_tile(leading, p.name, subtitle, on_tap: tap, trailing: trailing)
  end

  defp sp_status(%{status: :in_progress}), do: %{label: "接诊中", bg: 0x1F9A2E22, fg: :primary}
  defp sp_status(%{status: :completed}), do: %{label: "已完成", bg: 0x1F3E5C46, fg: :secondary}
  defp sp_status(_), do: %{label: "待接诊", bg: :surface_raised, fg: :muted}

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:patient, patient_id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.SimulatedPatientSessionScreen, %{
       patient_id: patient_id
     })}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
