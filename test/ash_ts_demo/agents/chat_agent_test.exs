defmodule AshTsDemo.Agents.ChatAgentTest do
  use ExUnit.Case, async: true

  @moduletag :ai

  alias AshTsDemo.Agents.MultiplyAction

  setup_all do
    has_key =
      System.get_env("DEEPSEEK_API_KEY") not in [nil, ""] or
        System.get_env("MINIMAX_API_KEY") not in [nil, ""]

    unless has_key do
      IO.puts("\n⚠️  Skipping AI tests: no LLM API key set")
    end

    {:ok, has_key: has_key}
  end

  # ============================================================
  # Direct ReAct runtime — no AgentServer required
  # ============================================================

  @tag :ai_integration
  test "simple question", ctx do
    if not ctx.has_key, do: return(:skipped)

    result =
      Jido.AI.Reasoning.ReAct.run("What is 2 + 2? Reply with just the number.", %{
        model: :fast,
        system_prompt: "You are a helpful math assistant. Be concise.",
        max_iterations: 3
      })

    assert is_map(result)
    answer = Map.get(result, :result) || Map.get(result, :answer) || ""
    assert is_binary(answer) and answer != ""
  end

  @tag :ai_integration
  test "uses multiply tool", ctx do
    if not ctx.has_key, do: return(:skipped)

    result =
      Jido.AI.Reasoning.ReAct.run(
        "Use the multiply tool: compute 17 × 9. Reply with the result.",
        %{
          model: :fast,
          system_prompt:
            "You are a math assistant. Always use the multiply tool for calculations.",
          tools: %{multiply: MultiplyAction},
          max_iterations: 5
        }
      )

    assert is_map(result)
    answer = Map.get(result, :result) || Map.get(result, :answer) || ""
    assert is_binary(answer) and answer != ""
    assert answer =~ "153" or String.contains?(answer, "153")
  end

  defp return(value), do: value
end
