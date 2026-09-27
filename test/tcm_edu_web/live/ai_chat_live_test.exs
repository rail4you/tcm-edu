defmodule TcmEduWeb.AiChatLiveTest do
  @moduledoc """
  最普通 AI 问答（`AiChatLive`，Jido AI + ReqLLM + Qwen）的功能测试。

  覆盖（不发真实 LLM 请求，发送路径用 `:none` key override 隔离）：

    * 学生端 `/ai-chat`：空态 → 新建会话 → 发送后用户消息即时落库展示
    * 会话隔离：看不到别人的会话
    * 教师端 `/teacher/ai/chat`：正常渲染
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Chat.ChatMessage
  alias TcmEdu.Chat.ChatSession

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

    student = create_user(:student)
    teacher = create_user(:teacher)

    student_conn =
      conn
      |> Plug.Test.init_test_session(%{
        "student_id" => student.id,
        "student_role" => "student",
        "student_tenant" => @tenant,
        "student_email" => to_string(student.email),
        "student_name" => "AI Chat Student"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: student_conn, student: student, teacher: teacher}
  end

  test "student creates a session and the sent message is stored", %{
    conn: conn,
    student: student
  } do
    conn
    |> visit("/ai-chat")
    |> assert_has("#qa-form")
    |> assert_has("#qa-messages", "比如")
    |> assert_has("nav", "AI 聊天")
    |> assert_has("nav a[href='/ai-chat']", "AI 聊天")
    |> click_button("新建会话")
    |> assert_has("aside", "新的问答")
    |> fill_in("问 AI 一个问题", with: "什么是经络？")
    |> click_button("发送")
    |> assert_has("#qa-messages", "什么是经络？")

    # 用户消息同步落库（assistant 回复因无 key 而失败，不落库）
    session_id = hd_session_id(student)

    assert {:ok, [message]} =
             ChatMessage
             |> Ash.Query.filter(session_id == ^session_id)
             |> Ash.Query.sort(inserted_at: :asc)
             |> Ash.read()

    assert message.role == "user"
    assert message.content == "什么是经络？"
  end

  test "renders knowledge-base references on assistant messages", %{conn: conn, student: student} do
    {:ok, session} = create_session(student, "知识库问答")

    {:ok, _} =
      ChatMessage
      |> Ash.Changeset.for_create(:create, %{
        session_id: session.id,
        role: "assistant",
        content: "桂枝汤由桂枝、芍药、甘草、生姜、大枣组成。",
        metadata: %{references: [%{title: "病例库：桂枝汤类方临证医案"}]}
      })
      |> Ash.create()

    conn
    |> visit("/ai-chat")
    |> assert_has("p", "桂枝汤由桂枝、芍药、甘草、生姜、大枣组成。")
    |> assert_has("span", "依据")
    |> assert_has("span", "病例库：桂枝汤类方临证医案")
  end

  test "sessions are isolated per user", %{conn: conn, student: student} do
    other = create_user(:student)
    {:ok, _} = create_session(other, "别人的会话")

    conn
    |> visit("/ai-chat")
    |> refute_has("aside", "别人的会话")

    {:ok, _} = create_session(student, "我的会话")

    conn
    |> visit("/ai-chat")
    |> assert_has("aside", "我的会话")
    |> refute_has("aside", "别人的会话")
  end

  test "teacher portal renders the same chat", %{teacher: teacher} do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "AI Chat Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    conn
    |> visit("/teacher/ai/chat")
    |> assert_has("#qa-form")
    |> assert_has("#new-session", "新建会话")
    |> assert_has("nav", "智能医疗")
    |> assert_has("nav a[href='/teacher/ai/chat']", "AI 问答")
  end

  # ── helpers ───────────────────────────────────────────────────

  defp create_user(role) do
    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{
        email: "ai-chat-#{role}-#{System.unique_integer([:positive])}@example.com",
        name: "AI Chat #{role}",
        password: "password123",
        role: role
      },
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()
  end

  defp create_session(user, title) do
    ChatSession
    |> Ash.Changeset.for_create(
      :create,
      %{user_id: user.id, agent_name: "qa_agent", title: title},
      actor: user
    )
    |> Ash.create()
  end

  defp hd_session_id(student) do
    {:ok, [session | _]} =
      ChatSession
      |> Ash.Query.for_read(:read, %{}, actor: student)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read(actor: student)

    session.id
  end
end
