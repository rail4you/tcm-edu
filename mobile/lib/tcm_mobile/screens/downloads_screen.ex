defmodule TcmMobile.Screens.DownloadsScreen do
  @moduledoc "学习资料 —— 列表 + 应用内预览（自托管 pdf.js）+ 应用内下载。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :resources, Api.list_downloads())}
  end

  @impl true
  def render(assigns) do
    rows = Enum.map(assigns.resources, &resource_row/1)

    hint =
      UI.card([
        ~MOB(<Text text="点按资料即可在应用内预览 PDF；点「下载到本地」把文件存进本机，不会跳转外部浏览器。" text_size={:sm} text_color={:muted} />)
      ])

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("学习资料")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_sm} fill_width={true}>
          {hint}
          {rows}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp resource_row(r) do
    open_tap = {self(), {:open, r.id}}
    tint = if r.downloaded, do: :secondary, else: :primary
    subtitle = if r.downloaded, do: "已下载 · #{r.size}", else: "#{r.type} · #{r.size}"

    UI.list_tile(UI.glyph_tile("资", tint, 40), r.title, subtitle, on_tap: open_tap)
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:open, id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.PdfViewerScreen, %{resource_id: id})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
