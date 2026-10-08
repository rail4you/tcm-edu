defmodule TcmEduWeb.TeacherAIKnowledgeQaLiveTest do
  @moduledoc """
  E2E coverage for the teacher knowledge-base Q&A page (`/teacher/ai/knowledge/qa`):

    * the left panel lists only knowledge sources that participate in Q&A,
    * sources excluded from Q&A are not listed but counted,
    * sending a question shows the user message immediately (LLM isolated via
      `api_key_override: :none`),
    * the teacher portal exposes a navigation entry.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Knowledge.TenantDoc

  @tenant "tenant_default"

  setup %{conn: conn} do
    old_ai_env = Application.get_env(:tcm_edu, TcmEdu.AI)
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    on_exit(fn ->
      case old_ai_env do
        nil -> Application.delete_env(:tcm_edu, TcmEdu.AI)
        env -> Application.put_env(:tcm_edu, TcmEdu.AI, env)
      end
    end)

    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "kb-qa-live-#{System.unique_integer([:positive])}@example.com",
          name: "KB QA Teacher",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "KB QA Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher}
  end

  test "lists available knowledge sources on the left", %{conn: conn, teacher: teacher} do
    {:ok, _} =
      create_doc(teacher, "outline.docx",
        title: "中医基础教学大纲",
        doc_type: :syllabus,
        content: "## 第一章 阴阳学说",
        embedded: true
      )

    conn
    |> visit("/teacher/ai/knowledge/qa")
    |> assert_has("aside", "可用文档")
    |> assert_has("aside", "中医基础教学大纲")
    |> assert_has(~s(#kb-doc-outline\\.docx), "中医基础教学大纲")
    |> assert_has("#kb-qa-form")
  end

  test "excludes sources not participating in Q&A but counts them", %{
    conn: conn,
    teacher: teacher
  } do
    {:ok, _} =
      create_doc(teacher, "available.docx",
        title: "可问答资料",
        content: "内容",
        embedded: true
      )

    {:ok, _} = create_doc(teacher, "private.docx", title: "未参与资料", in_chat: false)

    conn
    |> visit("/teacher/ai/knowledge/qa")
    |> assert_has("aside", "可问答资料")
    |> refute_has("aside", "未参与资料")
    |> assert_has("aside", "另有 1 份资料未参与问答")
  end

  test "shows an empty state when no source is available", %{conn: conn} do
    conn
    |> visit("/teacher/ai/knowledge/qa")
    |> assert_has("aside", "还没有可用资料")
  end

  test "sending a question shows the user message immediately", %{conn: conn} do
    conn
    |> visit("/teacher/ai/knowledge/qa")
    |> fill_in("基于知识库提问", with: "桂枝汤适用于哪些证候？")
    |> click_button("发送")
    |> assert_has("#kb-qa-messages", "桂枝汤适用于哪些证候？")
  end

  test "teacher portal exposes the knowledge Q&A navigation entry", %{conn: conn} do
    conn
    |> visit("/teacher/ai/knowledge/qa")
    |> assert_has("nav a[href='/teacher/ai/knowledge/qa']", "知识库问答")
  end

  # ── helpers ───────────────────────────────────────────────────

  defp create_doc(teacher, source_name, opts) do
    {:ok, doc} =
      TenantDoc.create_tenant_doc(
        %{
          title: opts[:title] || "资料",
          doc_type: opts[:doc_type] || :other,
          content: opts[:content] || "内容",
          source_name: source_name,
          indexed: Keyword.get(opts, :indexed, true),
          in_chat: Keyword.get(opts, :in_chat, true)
        },
        actor: teacher,
        tenant: @tenant
      )

    if opts[:embedded] do
      TenantDoc.mark_embedding_status(doc, %{embedding_status: :embedded},
        actor: teacher,
        tenant: @tenant
      )
    else
      {:ok, doc}
    end
  end
end
