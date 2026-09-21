defmodule TcmEdu.AI.AgentsTest do
  @moduledoc """
  AI 智能体测试（Req.Test mock）：
    * LessonPlan.generate 生成教案
    * MistakeExplainer.explain 错题解析
  不触达真实 DashScope。
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.{LessonPlan, MistakeExplainer}

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, TcmEdu.AI.AgentsTest}]
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "LessonPlan.generate returns a lesson plan" do
    Req.Test.stub(TcmEdu.AI.AgentsTest, fn conn ->
      assert conn.method == "POST"

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "# 《中医基础》教案\n## 教学目标\n..."}}]
      })
    end)

    assert {:ok, plan} =
             LessonPlan.generate(topic: "阴阳学说的基本内容", subject: "中医基础", level: "本科")

    assert plan =~ "# 《中医基础》教案"
  end

  test "LessonPlan.generate surfaces api error" do
    Req.Test.stub(TcmEdu.AI.AgentsTest, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        402,
        Jason.encode!(%{"error" => %{"message" => "Insufficient Balance"}})
      )
      |> Plug.Conn.halt()
    end)

    assert {:error, {:api, 402, _}} = LessonPlan.generate(topic: "瘀血证")
  end

  test "MistakeExplainer.explain returns analysis" do
    Req.Test.stub(TcmEdu.AI.AgentsTest, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "## 错因分析\n..."}}]})
    end)

    question = %{
      type: "single",
      stem: "丹参的功效不包括？",
      options: [
        %{"label" => "A", "text" => "活血祛瘀"},
        %{"label" => "B", "text" => "补气升阳"},
        %{"label" => "C", "text" => "凉血消痈"}
      ],
      answer: "B",
      explanation: "丹参活血调经、祛瘀止痛、凉血消痈、除烦安神；补气升阳是黄芪/升麻。"
    }

    assert {:ok, analysis} = MistakeExplainer.explain(question, "A")

    assert analysis =~ "错因分析"
  end

  test "MistakeExplainer.explain surfaces missing key" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} =
             MistakeExplainer.explain(%{stem: "?"}, "no-answer")
  end
end
