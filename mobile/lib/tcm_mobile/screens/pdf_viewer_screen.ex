defmodule TcmMobile.Screens.PdfViewerScreen do
  @moduledoc """
  学习资料预览 —— 用 WebView 内嵌 pdf.js 渲染 PDF（跨平台、离线缓存后可用）；
  「下载到本地 / 用系统打开」走 `Mob.Device.open_url/1`，交给系统原生查看器与
  下载管理器处理。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  # pdf.js 在线查看器：viewer.html?file=<url>
  @viewer "https://mozilla.github.io/pdf.js/web/viewer.html?file="

  @impl true
  def mount(%{resource_id: id}, _session, socket) do
    resource = Enum.find(Api.list_downloads(), &(&1.id == id))

    {:ok,
     socket
     |> Mob.Socket.assign(:resource, resource)
     |> Mob.Socket.assign(:downloaded?, resource.downloaded)}
  end

  @impl true
  def render(assigns) do
    r = assigns.resource
    viewer_url = @viewer <> URI.encode_www_form(r.url)
    open_tap = {self(), :open_native}
    download_tap = {self(), :download}

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header(r.title, {"forward", :open_native})}
      <WebView url={viewer_url} allow={["https://mozilla.github.io"]} weight={1} />
      <Row
        gap={:space_sm}
        padding={:space_md}
        background={:surface}
        border_color={:border}
        border_top_width={1}
        align={:center}
      >
        <Button
          text={if assigns.downloaded?, do: "已下载", else: "下载到本地"}
          on_tap={download_tap}
          weight={1}
          background={if assigns.downloaded?, do: :surface, else: :primary}
          text_color={if assigns.downloaded?, do: :on_surface, else: :on_primary}
        />
        <Button
          text="用系统打开"
          on_tap={open_tap}
          weight={1}
          background={:surface}
          text_color={:primary}
        />
      </Row>
    </Column>
    """
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, :open_native}, socket) do
    Mob.Device.open_url(socket.assigns.resource.url)
    {:noreply, socket}
  end

  def handle_info({:tap, :download}, socket) do
    Api.toggle_download(socket.assigns.resource.id)
    # 交给系统下载管理器 / 原生查看器
    Mob.Device.open_url(socket.assigns.resource.url)
    {:noreply, Mob.Socket.assign(socket, :downloaded?, true)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
