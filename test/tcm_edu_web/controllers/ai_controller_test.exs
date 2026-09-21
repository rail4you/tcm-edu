defmodule TcmEduWeb.AIControllerTest do
  @moduledoc """
  AI 控制器路由 + 错误路径 + Oban 入队测试。

  成功路径（真正调 Qwen/DashScope）需要 Mox 隔离，暂不覆盖；
  AI 模块本身已有 unit test（`TcmEdu.AI.*Test`）。
  """

  use TcmEduWeb.ConnCase, async: false

  import Oban.Testing, only: [assert_enqueued: 1]

  setup do
    # 提供测试 key（Application env override，避免 OS env 并发污染）
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: "sk-test-key")

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  describe "POST /api/ai/lesson_plan" do
    test "missing topic returns 400", %{conn: conn} do
      conn = post(conn, "/api/ai/lesson_plan", %{subject: "中医"})

      assert json = json_response(conn, 400)
      assert json["status"] == "error"
      assert json["reason"] =~ "missing topic"
    end

    test "with topic returns 502 when no API key configured", %{conn: conn} do
      Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

      conn = post(conn, "/api/ai/lesson_plan", %{topic: "阴阳学说", subject: "中医基础"})

      assert json = json_response(conn, 422)
      assert json["status"] == "error"
      assert json["reason"] =~ "missing_key"
    end
  end

  describe "POST /api/ai/image" do
    test "missing prompt returns 400", %{conn: conn} do
      conn = post(conn, "/api/ai/image", %{key_prefix: "ai"})

      assert json = json_response(conn, 400)
      assert json["status"] == "error"
      assert json["reason"] =~ "missing prompt"
    end

    test "with prompt returns 502 when no API key configured", %{conn: conn} do
      Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

      conn = post(conn, "/api/ai/image", %{prompt: "心脏解剖"})

      assert json = json_response(conn, 502)
      assert json["status"] == "error"
    end
  end

  describe "POST /api/ai/mistake_explain" do
    test "missing attempt_id returns 400", %{conn: conn} do
      conn = post(conn, "/api/ai/mistake_explain", %{})

      assert json = json_response(conn, 400)
      assert json["status"] == "error"
      assert json["reason"] =~ "missing attempt_id"
    end

    test "valid attempt_id queues a MistakeExplainer job", %{conn: conn} do
      # 我们不真正跑 AI，只确认 Oban 入队成功
      attempt_id = Ecto.UUID.generate()

      conn = post(conn, "/api/ai/mistake_explain", %{attempt_id: attempt_id})

      assert json = json_response(conn, 200)
      assert json["status"] == "queued"
      assert json["attempt_id"] == attempt_id

      assert_enqueued(
        worker: TcmEdu.Workers.MistakeExplainerWorker,
        args: %{"tenant" => "tenant_default", "attempt_id" => attempt_id},
        repo: TcmEdu.Repo
      )
    end
  end
end
