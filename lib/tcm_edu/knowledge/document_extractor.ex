defmodule TcmEdu.Knowledge.DocumentExtractor do
  @moduledoc """
  租户知识库文档文本提取（基于 `ExtractousEx` / Apache Tika）。

  支持 Word / Excel / PowerPoint / PDF / OpenDocument / 纯文本 / Markdown / CSV。
  用于教师上传教学大纲、病例库、手册等文档后，提取纯文本供
  `TcmEdu.Knowledge.TenantDoc` 分片 + 向量化。

  预编译 NIF（rustler_precompiled），无需本地 Rust 工具链。
  """

  alias ExtractousEx

  @supported_extensions ~w(.docx .xlsx .pptx .pdf .doc .xls .ppt .odt .ods .odp .txt .md .csv)
  @default_max_bytes 50 * 1024 * 1024

  @doc "支持的扩展名列表（用于上传白名单）"
  def supported_extensions, do: @supported_extensions

  @doc "文件扩展名是否受支持"
  @spec supported?(String.t()) :: boolean()
  def supported?(filename) when is_binary(filename) do
    Path.extname(filename) |> String.downcase() |> then(&(&1 in @supported_extensions))
  end

  @doc "上传大小上限（字节），可用 `Application.put_env(:tcm_edu, __MODULE__, max_bytes: n)` 覆盖（测试用）"
  def max_bytes,
    do: Application.get_env(:tcm_edu, __MODULE__, [])[:max_bytes] || @default_max_bytes

  @doc """
  从二进制 + 原始文件名提取纯文本。

  ## 返回

    * `{:ok, text}` — 提取并 trim 后的文本（空文档返回 `{:ok, ""}`）
    * `{:error, :empty}` / `{:error, :too_large}` / `{:error, {:unsupported_format, ext}}`
    * `{:error, reason}` — ExtractousEx 解析失败
  """
  @spec extract(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract(binary, filename) when is_binary(binary) and is_binary(filename) do
    cond do
      byte_size(binary) == 0 ->
        {:error, :empty}

      byte_size(binary) > max_bytes() ->
        {:error, :too_large}

      not supported?(filename) ->
        {:error, {:unsupported_format, Path.extname(filename)}}

      true ->
        case ExtractousEx.extract_from_bytes(binary, max_length: 500_000) do
          {:ok, %{content: content}} when is_binary(content) -> {:ok, String.trim(content)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Bang 版本：失败时抛错"
  @spec extract!(binary(), String.t()) :: String.t()
  def extract!(binary, filename) do
    case extract(binary, filename) do
      {:ok, text} -> text
      {:error, reason} -> raise "Document extraction failed: #{inspect(reason)}"
    end
  end

  @doc """
  结构化提取：返回文档的内容块序列，保留标题层级（供按章节分片）。

  Word 类（.docx/.doc/.odt）走 ExtractousEx 的 `xml: true` 模式解析 Tika
  XHTML（`<h1>/<h2>/<h3>/<p>`）；其余格式回退纯文本。

  ## 返回

    * `{:ok, [block]}`，block 为 `{:heading, text}` 或 `{:para, text}`
    * `{:error, reason}` — 同 `extract/2`
  """
  @spec extract_structured(binary(), String.t()) ::
          {:ok, [{atom(), String.t()}]} | {:error, term()}
  def extract_structured(binary, filename) when is_binary(binary) and is_binary(filename) do
    cond do
      byte_size(binary) == 0 ->
        {:error, :empty}

      byte_size(binary) > max_bytes() ->
        {:error, :too_large}

      not supported?(filename) ->
        {:error, {:unsupported_format, Path.extname(filename)}}

      heading_format?(filename) ->
        case ExtractousEx.extract_from_bytes(binary, xml: true, max_length: 500_000) do
          {:ok, %{content: xml}} when is_binary(xml) -> {:ok, parse_blocks(xml)}
          {:error, reason} -> {:error, reason}
        end

      true ->
        case extract(binary, filename) do
          {:ok, text} -> {:ok, [{:para, text}]}
          {:error, _} = error -> error
        end
    end
  end

  # Word 系格式才解析标题结构；表格类（xlsx）回退纯文本
  defp heading_format?(filename) do
    Path.extname(filename) |> String.downcase() |> then(&(&1 in ~w(.docx .doc .odt)))
  end

  # ── XHTML 解析 ─────────────────────────────────────────

  # Tika 输出是规则 XHTML（h1-h6 / p 标签，文本多为 UTF-8 中文）。
  # 直接用正则按块提取（避免 :xmerl 对非 latin1 编码的报错）。
  @xhtml_block ~r/<(h[1-6]|p)\b[^>]*>([\s\S]*?)<\/\1>/i

  defp parse_blocks(xml) do
    blocks =
      Regex.scan(@xhtml_block, xml)
      |> Enum.flat_map(fn [_full, tag, inner] ->
        text = strip_tags(inner)

        cond do
          text == "" ->
            []

          tag in ~w(h1 h2 h3 h4 h5 h6) ->
            [{:heading, text}]

          true ->
            [{:para, text}]
        end
      end)

    if blocks == [], do: [{:para, plain_text(xml)}], else: blocks
  end

  # 去内层标签并规整空白
  defp strip_tags(html) do
    html
    |> String.replace(~r/<[^>]+>/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # 兜底：从 XML 里剥离所有标签取可见文本
  defp plain_text(xml) do
    xml
    |> String.replace(~r/<[^>]+>/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
