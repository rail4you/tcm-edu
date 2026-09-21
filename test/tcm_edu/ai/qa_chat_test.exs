defmodule TcmEdu.AI.QaChatTest do
  @moduledoc """
  `TcmEdu.AI.QaChat`（Jido AI + ReqLLM + Qwen 纯问答）测试。

  不发真实请求：

    * `normalize_history/1` 纯函数规则
    * `ask/2` 未配置 key 时返回 `{:error, :missing_key}`
     （经 `TcmEdu.AI.api_key/0` 的 `:none` override）
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.QaChat

  setup do
    old = Application.get_env(:tcm_edu, TcmEdu.AI)
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    on_exit(fn ->
      case old do
        nil -> Application.delete_env(:tcm_edu, TcmEdu.AI)
        env -> Application.put_env(:tcm_edu, TcmEdu.AI, env)
      end
    end)

    :ok
  end

  test "normalize_history keeps only user/assistant messages with content" do
    history = [
      %{role: "user", content: "什么是经络？"},
      %{role: "assistant", content: "经络是…"},
      %{role: "system", content: "ignored"},
      %{role: "user", content: "   "},
      %{role: "tool", content: "ignored"},
      %{role: :user, content: :atom_content}
    ]

    assert QaChat.normalize_history(history) == [
             %{role: "user", content: "什么是经络？"},
             %{role: "assistant", content: "经络是…"},
             %{role: "user", content: "atom_content"}
           ]
  end

  test "normalize_history caps at the most recent #{20} messages" do
    history =
      for i <- 1..30 do
        %{role: "user", content: "问题 #{i}"}
      end

    normalized = QaChat.normalize_history(history)

    assert length(normalized) == QaChat.default_history_limit()
    assert List.first(normalized) == %{role: "user", content: "问题 11"}
    assert List.last(normalized) == %{role: "user", content: "问题 30"}
  end

  test "ask/2 returns missing_key when no Qwen key is configured" do
    assert {:error, :missing_key} = QaChat.ask("什么是阴阳五行？", history: [])
  end

  test "system_prompt is a non-empty Chinese assistant prompt" do
    prompt = QaChat.system_prompt()
    assert is_binary(prompt) and byte_size(prompt) > 10
  end
end
