defmodule TcmEdu.Knowledge.TenantDocTest do
  @moduledoc """
  租户知识文档测试（AshAi vectorize · :manual 策略）。

  覆盖：
    * 创建文档 → 初始 embedding_status = :pending
    * Oban worker 调 :ash_ai_update_embeddings 写入 full_text_vector → :embedded
    * 语义搜索按相关度排序（Req.Test stub 用关键字生成确定性向量）
    * 权限：教师/管理员可建，学生只读；学生不可建
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Knowledge.TenantDoc
  alias TcmEdu.Workers.TenantDocEmbeddingWorker

  @tenant "tenant_default"
  @stub TcmEdu.Knowledge.TenantDocTest

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

  describe "create / embedding worker" do
    test "creating a doc leaves status pending; worker embeds it" do
      teacher = create_user!(:teacher)

      {:ok, doc} =
        TenantDoc.create_tenant_doc(
          %{
            title: "病例库：桂枝汤类方临证医案",
            doc_type: :case_library,
            content: "典型病例：患者恶风、发热、汗出、脉浮缓，治以桂枝汤。"
          },
          actor: teacher,
          tenant: @tenant
        )

      assert doc.embedding_status == :pending

      Phoenix.PubSub.subscribe(TcmEdu.PubSub, TenantDocEmbeddingWorker.topic(@tenant))

      assert :ok =
               TenantDocEmbeddingWorker.perform(%Oban.Job{
                 args: %{"tenant" => @tenant, "doc_id" => doc.id}
               })

      assert_receive {:knowledge_docs_event, :doc_embedded, payload}
      assert payload.doc_id == doc.id
      assert payload.embedding_status == :embedded
      assert payload.source_name == doc.source_name

      embedded = TenantDoc.get_tenant_doc!(doc.id, tenant: @tenant, authorize?: false)
      assert embedded.embedding_status == :embedded
      assert is_nil(embedded.error_message)

      loaded = Ash.load!(embedded, :full_text_vector)
      assert %Ash.Vector{} = loaded.full_text_vector
      assert length(Ash.Vector.to_list(loaded.full_text_vector)) == 1024
    end

    test "worker marks failed when embedding API errors" do
      teacher = create_user!(:teacher)

      {:ok, doc} =
        TenantDoc.create_tenant_doc(
          %{title: "坏文档", content: "桂枝"},
          actor: teacher,
          tenant: @tenant
        )

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => %{"message" => "boom"}}))
        |> Plug.Conn.halt()
      end)

      assert {:error, "embedding failed"} =
               TenantDocEmbeddingWorker.perform(%Oban.Job{
                 args: %{"tenant" => @tenant, "doc_id" => doc.id}
               })

      failed = TenantDoc.get_tenant_doc!(doc.id, tenant: @tenant, authorize?: false)
      assert failed.embedding_status == :failed
      assert failed.error_message == "embedding generation failed"
    end
  end

  describe "semantic search" do
    setup do
      teacher = create_user!(:teacher)

      {:ok, case_doc} =
        TenantDoc.create_tenant_doc(
          %{
            title: "病例库：桂枝汤类方临证医案",
            doc_type: :case_library,
            content: "典型病例：患者恶风、发热、汗出、脉浮缓，治以桂枝汤，啜热稀粥温覆取微汗。"
          },
          actor: teacher,
          tenant: @tenant
        )

      {:ok, syllabus_doc} =
        TenantDoc.create_tenant_doc(
          %{
            title: "2025 中医基础理论教学大纲",
            doc_type: :syllabus,
            content: "第一章 阴阳学说，第二章 五行学说，第三章 藏象学说，第四章 气血津液。"
          },
          actor: teacher,
          tenant: @tenant
        )

      Enum.each([case_doc, syllabus_doc], fn doc ->
        :ok =
          TenantDocEmbeddingWorker.perform(%Oban.Job{
            args: %{"tenant" => @tenant, "doc_id" => doc.id}
          })
      end)

      %{case_doc: case_doc, syllabus_doc: syllabus_doc}
    end

    test "query about 桂枝汤 ranks the case library first" do
      assert {:ok, hits} =
               TcmEdu.Knowledge.search_top_docs(@tenant, "桂枝汤治疗太阳中风", 5)

      assert [%{title: first} | _] = hits
      assert first =~ "病例库"
    end

    test "query about 阴阳 ranks the syllabus first" do
      assert {:ok, hits} =
               TcmEdu.Knowledge.search_top_docs(@tenant, "阴阳五行学说", 5)

      assert [%{title: first} | _] = hits
      assert first =~ "教学大纲"
    end

    test "student can search the knowledge base" do
      student = create_user!(:student)

      assert {:ok, [%{title: first} | _]} =
               TenantDoc.search_tenant_docs(%{query: "桂枝汤", k: 5},
                 actor: student,
                 tenant: @tenant
               )

      assert first =~ "病例库"
    end
  end

  describe "policies" do
    test "student cannot create a tenant doc" do
      student = create_user!(:student)

      assert {:error, %Ash.Error.Forbidden{}} =
               TenantDoc
               |> Ash.Changeset.for_action(:create, %{title: "X", content: "Y"},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end

    test "teacher can create and read tenant docs" do
      teacher = create_user!(:teacher)

      assert {:ok, %TenantDoc{title: title}} =
               TenantDoc.create_tenant_doc(
                 %{title: "教师手册", content: "桂枝"},
                 actor: teacher,
                 tenant: @tenant
               )

      assert title == "教师手册"

      list = TenantDoc.list_tenant_docs!(actor: teacher, tenant: @tenant)
      assert Enum.any?(list, &(&1.title == "教师手册"))
    end
  end

  # ─── Req.Test stub：确定性向量，便于断言排序 ─────────────

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

  # 关键字 → 主导维度：桂枝=0，阴阳=1，其余=2
  defp vector_for(text) do
    idx =
      if String.contains?(text, "桂枝"),
        do: 0,
        else: if(String.contains?(text, "阴阳"), do: 1, else: 2)

    unit(idx)
  end

  # 1024 维近似单位向量：第 idx 维为 1，其余 0.001（使余弦距离在匹配时≈0，不匹配时>0.6）
  defp unit(idx) do
    vec = List.duplicate(0.001, 1024) |> List.replace_at(idx, 1.0)
    norm = :math.sqrt(Enum.sum(Enum.map(vec, fn x -> x * x end)))
    Enum.map(vec, fn x -> x / norm end)
  end

  # ─── helpers ───────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "knowledge-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end
end
