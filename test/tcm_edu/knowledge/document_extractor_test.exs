defmodule TcmEdu.Knowledge.DocumentExtractorTest do
  @moduledoc """
  DocumentExtractor 测试（真实 NIF 解析，xlsx 样本用 elixlsx 现场生成）。

  覆盖：
    * xlsx → 提取中文表格文本
    * docx → 提取标题/段落（fixture 用最小 OOXML 包）
    * 边界：空二进制 / 超限 / 不支持扩展名
  """

  use ExUnit.Case, async: true

  alias Elixlsx.{Sheet, Workbook}
  alias TcmEdu.Knowledge.DocumentExtractor

  describe "xlsx extraction" do
    test "extracts Chinese spreadsheet content" do
      xlsx = build_xlsx!()

      assert {:ok, text} = DocumentExtractor.extract(xlsx, "题库.xlsx")
      assert text =~ "桂枝汤"
      assert text =~ "太阳中风证"
    end
  end

  describe "docx extraction" do
    test "extracts paragraphs from a minimal OOXML package" do
      docx = build_docx!("中医基础理论教学大纲", "第一章 阴阳学说")

      assert {:ok, text} = DocumentExtractor.extract(docx, "教学大纲.docx")
      assert text =~ "中医基础理论教学大纲"
      assert text =~ "第一章 阴阳学说"
    end

    test "extract_structured parses headings and paragraphs" do
      docx = build_outline_docx!()

      assert {:ok, blocks} = DocumentExtractor.extract_structured(docx, "教学大纲.docx")

      assert {:heading, "中医基础理论教学大纲"} in blocks
      assert {:heading, "第一章 阴阳学说"} in blocks
      assert {:para, para} = Enum.find(blocks, &match?({:para, _}, &1))
      assert para =~ "阴阳"
    end
  end

  describe "validation" do
    test "rejects empty binary" do
      assert {:error, :empty} = DocumentExtractor.extract(<<>>, "a.docx")
    end

    test "rejects oversized binary" do
      Application.put_env(:tcm_edu, DocumentExtractor, max_bytes: 10)
      on_exit(fn -> Application.delete_env(:tcm_edu, DocumentExtractor) end)

      assert {:error, :too_large} = DocumentExtractor.extract("0123456789X", "a.docx")
    end

    test "rejects unsupported extension" do
      assert {:error, {:unsupported_format, ".exe"}} =
               DocumentExtractor.extract("MZ...", "virus.exe")
    end

    test "supports the expected extensions" do
      for ext <- ~w(.docx .xlsx .pptx .pdf .doc .xls .ppt .odt .ods .odp .txt .md .csv) do
        assert DocumentExtractor.supported?("file#{ext}")
      end

      refute DocumentExtractor.supported?("file.rar")
    end
  end

  # 带标题（Heading1/Heading2 pStyle）的 docx，Tika 会渲染为 h1/h2
  defp build_outline_docx! do
    document_xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>中医基础理论教学大纲</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>第一章 阴阳学说</w:t></w:r></w:p>
        <w:p><w:r><w:t>阴阳是对立统一的两面。</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>第二章 五行学说</w:t></w:r></w:p>
        <w:p><w:r><w:t>五行相生相克。</w:t></w:r></w:p>
      </w:body>
    </w:document>
    """

    content_types = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    </Types>
    """

    rels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    document_rels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    styles_xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:style w:type="paragraph" w:styleId="Heading1">
        <w:name w:val="heading 1"/>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading2">
        <w:name w:val="heading 2"/>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Normal">
        <w:name w:val="Normal"/>
      </w:style>
    </w:styles>
    """

    zip_path = Path.join(System.tmp_dir!(), "outline-#{System.unique_integer([:positive])}.docx")
    File.rm(zip_path)

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [
          {~c"[Content_Types].xml", content_types},
          {~c"_rels/.rels", rels},
          {~c"word/document.xml", document_xml},
          {~c"word/_rels/document.xml.rels", document_rels},
          {~c"word/styles.xml", styles_xml}
        ]
      )

    on_exit(fn -> File.rm(zip_path) end)
    File.read!(zip_path)
  end

  # ─── helpers ───────────────────────────────────────────

  defp build_xlsx! do
    sheet = %Sheet{
      name: "题库",
      rows: [
        ["题号", "题干", "答案"],
        [1, "桂枝汤的组成药物不包括？", "麻黄"],
        [2, "太阳中风证的治法？", "解肌发表，调和营卫"]
      ]
    }

    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "题库.xlsx")
    binary
  end

  # 最小 docx：OOXML 是 zip，手动构造 document.xml
  defp build_docx!(title, body) do
    document_xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p><w:r><w:t>#{title}</w:t></w:r></w:p>
        <w:p><w:r><w:t>#{body}</w:t></w:r></w:p>
      </w:body>
    </w:document>
    """

    content_types = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    rels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    zip_path = Path.join(System.tmp_dir!(), "minimal-#{System.unique_integer([:positive])}.docx")
    File.rm(zip_path)

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [
          {~c"[Content_Types].xml", content_types},
          {~c"_rels/.rels", rels},
          {~c"word/document.xml", document_xml}
        ]
      )

    on_exit(fn -> File.rm(zip_path) end)
    File.read!(zip_path)
  end
end
