defmodule TcmEdu.Agents.MultiplyActionTest do
  use ExUnit.Case, async: true

  alias TcmEdu.Agents.MultiplyAction

  test "multiplies integers" do
    {:ok, result} = MultiplyAction.run(%{a: 7, b: 8}, %{})
    assert result.result == 56.0
  end

  test "multiplies decimals" do
    {:ok, result} = MultiplyAction.run(%{a: 2.5, b: 4}, %{})
    assert result.result == 10.0
  end

  test "multiplies negatives" do
    {:ok, result} = MultiplyAction.run(%{a: -3, b: 6}, %{})
    assert result.result == -18.0
  end
end
