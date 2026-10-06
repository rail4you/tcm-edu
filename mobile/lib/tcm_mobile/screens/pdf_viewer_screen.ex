defmodule TcmMobile.Screens.PdfViewerScreen do
  @moduledoc """
  学习资料预览 —— WebView 内嵌**自托管**的 pdf.js（后端
  `/pdfjs/web/viewer.html`，锁在 4.6.82 的 legacy 构建，兼容系统 WebView
  的旧内核）渲染 PDF。

  PDF 本体一律经后端同源转发 `/pdfjs/doc?u=…` 取回：viewer 与 PDF 同源，
  浏览器根本不走 CORS，上游（演示占位站 / OSS）也就无需配置跨域白名单。
  上游主机由后端的 `:pdf_proxy_hosts` 白名单限制，不是开放代理。

  「下载到本地」在本进程里经后端同源转发把字节拉下来、写进应用下载目录，
  并尽力同步一份到系统媒体库——不再跳出外部浏览器。「用系统打开」仍交给
  原生查看器（那是它名字的意思，本来就该跳出去）。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(%{resource_id: id}, _session, socket) do
    resource = Enum.find(Api.list_downloads(), &(&1.id == id))

    {:ok,
     socket
     |> Mob.Socket.assign(:resource, resource)
     |> Mob.Socket.assign(:downloaded?, resource.downloaded)
     |> Mob.Socket.assign(:downloading?, false)}
  end

  @impl true
  def render(assigns) do
    r = assigns.resource
    origin = Api.web_base_url()
    viewer_url = viewer_url(origin, r.url)
    open_tap = {self(), :open_native}
    download_tap = {self(), :download}

    download_label =
      cond do
        assigns.downloading? -> "下载中…"
        assigns.downloaded? -> "已下载"
        true -> "下载到本地"
      end

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header(r.title, {"forward", :open_native})}
      <WebView url={viewer_url} allow={[origin]} weight={1} />
      <Row
        gap={:space_sm}
        padding={:space_md}
        background={:surface}
        border_color={:border}
        border_top_width={1}
        align={:center}
      >
        <Button
          text={download_label}
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

  # 外层 `file=` 是自托管 viewer 的地址，里层是它去取 PDF 的同源转发地址
  # （`Api.proxy_pdf_url/1`）。两层都只保留非保留字符，避免 `?`/`&` 被提前
  # 截断成参数。
  defp viewer_url(origin, pdf_url) do
    origin <>
      "/pdfjs/web/viewer.html?file=" <>
      URI.encode(Api.proxy_pdf_url(pdf_url), &URI.char_unreserved?/1)
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, :open_native}, socket) do
    Mob.Device.open_url(socket.assigns.resource.url)
    {:noreply, socket}
  end

  def handle_info({:tap, :download}, socket) do
    if socket.assigns.downloading? or socket.assigns.downloaded? do
      {:noreply, socket}
    else
      screen = self()
      url = socket.assigns.resource.url

      Task.start(fn -> send(screen, {:pdf_saved, save_to_disk(url)}) end)

      {:noreply, Mob.Socket.assign(socket, :downloading?, true)}
    end
  end

  def handle_info({:pdf_saved, {:ok, path}}, socket) do
    Api.toggle_download(socket.assigns.resource.id)

    socket
    |> Mob.Socket.assign(:downloaded?, true)
    |> Mob.Socket.assign(:downloading?, false)
    |> publish_to_media_store(path)
    |> then(&{:noreply, Mob.Alert.toast(&1, "已下载：#{Path.basename(path)}")})
  end

  def handle_info({:pdf_saved, {:error, reason}}, socket) do
    socket
    |> Mob.Socket.assign(:downloading?, false)
    |> then(&{:noreply, Mob.Alert.toast(&1, "下载失败：#{reason}")})
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # 尽力把文件推进系统媒体库（Android 的「文件/下载」里就能看到）。
  # iOS 没有这个 NIF，直接跳过——文件仍留在应用下载目录。
  defp publish_to_media_store(socket, path) do
    if function_exported?(:mob_nif, :storage_save_to_media_store, 2) do
      Mob.Storage.Android.save_to_media_store(socket, path, :auto)
    else
      socket
    end
  end

  defp save_to_disk(url) do
    with {:ok, body} <- fetch_pdf(url),
         {:ok, dir} <- download_dir(),
         path = Path.join(dir, filename(url)),
         {:ok, _written} <- Mob.Storage.write(path, body) do
      {:ok, path}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _posix} -> {:error, "写入存储失败"}
      _ -> {:error, "下载失败"}
    end
  rescue
    # 网络/TLS/存储层的任何异常都要落回一条消息，否则按钮会永远卡在
    # 「下载中…」——Task 崩了就没有人再来收尾。
    _error -> {:error, "下载失败"}
  end

  defp fetch_pdf(url) do
    # 走后端同源转发：设备侧 BEAM 没有可用的 `:crypto`，https 直连必挂在
    # TLS 握手上；后端代理跑在宿主机，由它去连上游。
    case Req.get(Api.proxy_pdf_url(url),
           decode_body: false,
           retry: false,
           receive_timeout: 60_000
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        if is_binary(body), do: {:ok, body}, else: {:error, "响应不是文件内容"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "上游返回 #{status}"}

      {:error, _reason} ->
        {:error, "连不上服务器"}
    end
  end

  defp download_dir do
    case Mob.Storage.Android.external_files_dir(:downloads) do
      nil -> {:ok, Mob.Storage.dir(:documents)}
      dir -> {:ok, dir}
    end
  end

  defp filename(url) do
    base =
      case URI.new(url) do
        {:ok, %URI{path: path}} when is_binary(path) -> Path.basename(path)
        _ -> ""
      end

    if String.match?(base, ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\.pdf\z/) do
      base
    else
      "document.pdf"
    end
  end
end
