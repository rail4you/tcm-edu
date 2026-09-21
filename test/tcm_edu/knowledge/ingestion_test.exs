defmodule TcmEdu.Knowledge.IngestionTest do
  @moduledoc """
  知识库入库测试：
    * chunk/2 分片逻辑（短文本、合并、超长段落硬切、Unicode 安全）
    * ingest/3 端到端：xlsx 提取 → 建 TenantDoc → enqueue 嵌入 worker
    * 空/不支持格式报错
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias Elixlsx.{Sheet, Workbook}
  alias TcmEdu.Accounts.User
  alias TcmEdu.Knowledge.Ingestion
  alias TcmEdu.Knowledge.TenantDoc
  alias TcmEdu.Workers.TenantDocEmbeddingWorker

  @tenant "tenant_default"
  @stub TcmEdu.Knowledge.IngestionTest

  setup do
    req_opts = [plug: {Req.Test, @stub}]

    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      embedding_model: "text-embedding-v3",
      embedding_dimensions: 1024,
      timeout: 5_000,
      req_options: req_opts
    )

    Req.Test.stub(@stub, &test_embed_stub/1)

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  describe "chunk/2" do
    test "empty text yields no chunks" do
      assert Ingestion.chunk("") == []
      assert Ingestion.chunk("   \n\n  ") == []
    end

    test "short text stays one chunk" do
      assert Ingestion.chunk("第一章 阴阳学说", 1200) == ["第一章 阴阳学说"]
    end

    test "paragraphs under limit are merged" do
      text = "第一段\n\n第二段\n第三段"

      assert Ingestion.chunk(text, 1200) == ["第一段\n第二段\n第三段"]
    end

    test "paragraphs over limit split into multiple chunks" do
      # 每段 30 字，limit 50 → 第一段独立、二+三段合并
      text =
        "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸" <>
          "\n" <>
          "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸" <>
          "\n" <>
          "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸"

      chunks = Ingestion.chunk(text, 50)
      assert length(chunks) == 2
      assert Enum.all?(chunks, &(String.length(&1) <= 50))
    end

    test "a single over-long paragraph is hard-split on unicode boundary" do
      # 每个字都是多字节
      long = String.duplicate("阴阳五行藏象经络气血津液", 50)

      chunks = Ingestion.chunk(long, 100)

      assert length(chunks) > 1
      assert Enum.all?(chunks, &(String.length(&1) <= 100))
      # 拼接回去应等于原文（无字符丢失/错乱）
      assert Enum.join(chunks, "") == long
    end
  end

  describe "chunk_blocks/2" do
    test "groups blocks into heading sections" do
      blocks = [
        {:heading, "中医基础理论教学大纲"},
        {:heading, "第一章 阴阳学说"},
        {:para, "阴阳是对立统一的两面。"},
        {:para, "寒者热之，热者寒之。"},
        {:heading, "第二章 五行学说"},
        {:para, "五行相生相克。"}
      ]

      chunks = Ingestion.chunk_blocks(blocks, 500)

      assert length(chunks) == 3

      assert Enum.any?(chunks, &(&1 == "## 中医基础理论教学大纲"))

      assert Enum.any?(chunks, fn c ->
               c =~ "## 第一章 阴阳学说" and c =~ "阴阳是对立统一的两面。" and c =~ "寒者热之"
             end)

      assert Enum.any?(chunks, fn c ->
               c =~ "## 第二章 五行学说" and c =~ "五行相生相克。"
             end)
    end

    test "a section longer than the limit is hard-split" do
      long = String.duplicate("阴阳五行藏象经络", 20)
      blocks = [{:heading, "第一章"}, {:para, long}]

      chunks = Ingestion.chunk_blocks(blocks, 50)

      assert length(chunks) > 1
      assert Enum.all?(chunks, &(String.length(&1) <= 50))

      # 标题超限场景下独立成块（6 + 50 > 50），去掉标题前缀后拼接应还原原文
      assert Enum.join(chunks, "") |> String.replace_prefix("## 第一章", "") == long
    end
  end

  describe "source switches" do
    test "update_source toggles indexed/in_chat on all chunks" do
      teacher = create_user!(:teacher)

      {:ok, docs} =
        Ingestion.ingest(@tenant, teacher, %{
          filename: "switch.xlsx",
          content: build_xlsx!(),
          title: "开关测试",
          doc_type: :case_library
        })

      assert docs != []

      assert {:ok, count} =
               Ingestion.update_source(@tenant, teacher, "switch.xlsx", %{
                 in_chat: false,
                 indexed: false
               })

      assert count == length(docs)

      updated = TenantDoc.list_tenant_docs!(tenant: @tenant, authorize?: false)
      switched = Enum.filter(updated, &(&1.source_name == "switch.xlsx"))
      assert Enum.all?(switched, &(&1.in_chat == false))
      assert Enum.all?(switched, &(&1.indexed == false))
    end

    test "search excludes sources with the chat switch off" do
      teacher = create_user!(:teacher)

      {:ok, [doc]} =
        Ingestion.ingest(@tenant, teacher, %{
          filename: "cases.xlsx",
          content: build_xlsx!(),
          title: "桂枝汤病例",
          doc_type: :case_library
        })

      # 真实跑一次嵌入，让向量可检索
      :ok =
        TenantDocEmbeddingWorker.perform(%Oban.Job{
          args: %{"tenant" => @tenant, "doc_id" => doc.id}
        })

      # 普通检索命中
      assert {:ok, [%{title: "桂枝汤病例"}]} = TcmEdu.Knowledge.search_top_docs(@tenant, "桂枝汤", 5)

      # 关闭问答 → in_chat_only 检索不命中
      Ingestion.update_source(@tenant, teacher, "cases.xlsx", %{in_chat: false})

      assert {:ok, []} = TcmEdu.Knowledge.search_top_docs(@tenant, "桂枝汤", 5, in_chat_only: true)

      # 普通检索仍命中
      assert {:ok, [_ | _]} = TcmEdu.Knowledge.search_top_docs(@tenant, "桂枝汤", 5)
    end

    test "worker skips indexing when indexed is false" do
      teacher = create_user!(:teacher)

      {:ok, [doc]} =
        Ingestion.ingest(@tenant, teacher, %{
          filename: "skip.xlsx",
          content: build_xlsx!(),
          title: "跳过索引"
        })

      Ingestion.update_source(@tenant, teacher, "skip.xlsx", %{indexed: false})

      assert :ok =
               TenantDocEmbeddingWorker.perform(%Oban.Job{
                 args: %{"tenant" => @tenant, "doc_id" => doc.id}
               })

      updated = TenantDoc.get_tenant_doc!(doc.id, tenant: @tenant, authorize?: false)
      # 不索引 → 不调 embedding，但状态置 embedded（跳过）
      assert updated.embedding_status == :embedded
      loaded = Ash.load!(updated, :full_text_vector)
      assert is_nil(loaded.full_text_vector)
    end
  end

  describe "media ingestion" do
    test "ingest_media stores an image and creates an unindexed media doc" do
      teacher = create_user!(:teacher)

      # stub OSS PUT + embedding（区分 path）
      Req.Test.stub(@stub, fn conn ->
        if String.ends_with?(conn.request_path, "/embeddings") do
          test_embed_stub(conn)
        else
          conn
          |> Plug.Conn.put_resp_content_type("application/xml")
          |> Plug.Conn.send_resp(200, "<PostResponse/>")
        end
      end)

      png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "fake", "png", "data">>

      {:ok, doc} =
        Ingestion.ingest_media(@tenant, teacher, %{
          filename: "穴位图.png",
          content: png,
          media_kind: :image,
          title: "手太阴肺经穴位图"
        })

      assert doc.media_kind == :image
      assert doc.indexed == false
      assert doc.in_chat == false
      assert doc.thumbnail_url =~ "x-oss-process=image/resize"
      assert doc.thumbnail_url =~ "w_300"
      # 媒体资源不参与问答检索
      assert {:ok, []} = TcmEdu.Knowledge.search_top_docs(@tenant, "手太阴肺经", 5, in_chat_only: true)
    end
  end

  describe "ingest/3" do
    setup do
      teacher = create_user!(:teacher)
      %{teacher: teacher}
    end

    test "extracts xlsx, creates TenantDocs and enqueues embedding workers", %{teacher: teacher} do
      xlsx = build_xlsx!()

      assert {:ok, docs} =
               Ingestion.ingest(@tenant, teacher, %{
                 filename: "病例库.xlsx",
                 content: xlsx,
                 title: "病例库：桂枝汤类方",
                 doc_type: :case_library
               })

      assert docs != []
      assert Enum.all?(docs, &(&1.embedding_status == :pending))
      assert Enum.all?(docs, &(&1.source_name == "病例库.xlsx"))

      content = Enum.map_join(docs, "\n", & &1.content)
      assert content =~ "桂枝汤"

      assert Oban.Testing.all_enqueued(queue: :default, repo: TcmEdu.Repo) |> length() ==
               length(docs)
    end

    test "splits a headed docx into per-section TenantDocs", %{teacher: teacher} do
      docx = build_outline_docx!()

      assert {:ok, docs} =
               Ingestion.ingest(@tenant, teacher, %{
                 filename: "教学大纲.docx",
                 content: docx,
                 title: "中医基础教学大纲",
                 doc_type: :syllabus
               })

      assert length(docs) >= 3
      assert Enum.all?(docs, &(&1.title == "中医基础教学大纲"))
      assert Enum.all?(docs, &(&1.source_name == "教学大纲.docx"))
      assert Enum.all?(docs, &(&1.embedding_status == :pending))

      contents = Enum.map(docs, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "## 第一章 阴阳学说"))
      assert Enum.any?(contents, &String.contains?(&1, "## 第二章 五行学说"))
    end

    test "unsupported format returns error", %{teacher: teacher} do
      assert {:error, {:unsupported_format, ".exe"}} =
               Ingestion.ingest(@tenant, teacher, %{filename: "a.exe", content: "MZ"})
    end

    test "empty document returns error", %{teacher: teacher} do
      assert {:error, :empty} =
               Ingestion.ingest(@tenant, teacher, %{filename: "空.docx", content: ""})
    end
  end

  # ─── Req.Test stub：确定性向量（含"桂枝"→强维度，便于检索命中） ─────

  def test_embed_stub(conn) do
    inputs = get_in(conn.body_params, ["input"]) || []

    data =
      inputs
      |> Enum.with_index()
      |> Enum.map(fn {text, i} -> %{"embedding" => vector_for(text), "index" => i} end)

    Req.Test.json(conn, %{
      "data" => data,
      "model" => "text-embedding-v3",
      "usage" => %{"prompt_tokens" => 1, "total_tokens" => 1}
    })
  end

  defp vector_for(text) do
    idx = if String.contains?(text, "桂枝"), do: 0, else: 1
    vec = List.duplicate(0.001, 1024) |> List.replace_at(idx, 1.0)
    norm = :math.sqrt(Enum.sum(Enum.map(vec, fn x -> x * x end)))
    Enum.map(vec, fn x -> x / norm end)
  end

  # ─── helpers ───────────────────────────────────────────

  # 带 Heading1/Heading2 的 docx（Tika 渲染为 h1/h2）
  defp build_outline_docx! do
    document_xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>中医基础理论教学大纲</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>第一章 阴阳学说</w:t></w:r></w:p>
        <w:p><w:r><w:t>阴阳是对立统一的两面，寒者热之。</w:t></w:r></w:p>
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

    package_rels = """
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
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>
      <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style>
      <w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    </w:styles>
    """

    zip_path =
      Path.join(System.tmp_dir!(), "ingest-outline-#{System.unique_integer([:positive])}.docx")

    File.rm(zip_path)

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [
          {~c"[Content_Types].xml", content_types},
          {~c"_rels/.rels", package_rels},
          {~c"word/document.xml", document_xml},
          {~c"word/_rels/document.xml.rels", document_rels},
          {~c"word/styles.xml", styles_xml}
        ]
      )

    on_exit(fn -> File.rm(zip_path) end)
    File.read!(zip_path)
  end

  defp build_xlsx! do
    sheet = %Sheet{
      name: "病例库",
      rows: [
        ["编号", "主诉", "辨证"],
        [1, "恶风发热汗出脉浮缓", "太阳中风证，治以桂枝汤"],
        [2, "项背强几几", "桂枝加葛根汤"]
      ]
    }

    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "病例库.xlsx")
    binary
  end

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "ingestion-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end
end
