defmodule TcmEdu.Agents.CounterAgentTest do
  use ExUnit.Case, async: true

  alias TcmEdu.Agents.{
    CounterAgent,
    IncrementAction,
    DecrementAction,
    ResetAction,
    SetAction
  }

  describe "new/1" do
    test "creates an agent with default state" do
      agent = CounterAgent.new()
      assert agent.state.count == 0
      assert agent.state.status == :idle
    end
  end

  describe "IncrementAction" do
    test "increments by default amount (1)" do
      agent = CounterAgent.new()
      {agent, directives} = CounterAgent.cmd(agent, IncrementAction)

      assert agent.state.count == 1
      assert directives == []
    end

    test "increments by specified amount" do
      agent = CounterAgent.new()
      {agent, directives} = CounterAgent.cmd(agent, {IncrementAction, %{by: 10}})

      assert agent.state.count == 10
      assert directives == []
    end

    test "handles chained increments" do
      agent = CounterAgent.new()

      {agent, _} = CounterAgent.cmd(agent, {IncrementAction, %{by: 5}})
      {agent, _} = CounterAgent.cmd(agent, {IncrementAction, %{by: 3}})
      {agent, _} = CounterAgent.cmd(agent, IncrementAction)

      assert agent.state.count == 9
    end
  end

  describe "DecrementAction" do
    test "decrements by default amount (1)" do
      agent = CounterAgent.new()
      {agent, _} = CounterAgent.cmd(agent, DecrementAction)

      assert agent.state.count == -1
    end

    test "decrements by specified amount" do
      agent = CounterAgent.new()
      # Start at 10, then decrement by 4
      {agent, _} = CounterAgent.cmd(agent, {SetAction, %{value: 10}})
      {agent, _} = CounterAgent.cmd(agent, {DecrementAction, %{by: 4}})

      assert agent.state.count == 6
    end
  end

  describe "ResetAction" do
    test "resets counter to zero" do
      agent = CounterAgent.new()
      {agent, _} = CounterAgent.cmd(agent, {IncrementAction, %{by: 42}})
      assert agent.state.count == 42

      {agent, _} = CounterAgent.cmd(agent, ResetAction)
      assert agent.state.count == 0
      assert agent.state.status == :idle
    end
  end

  describe "SetAction" do
    test "sets counter to a specific value" do
      agent = CounterAgent.new()
      {agent, _} = CounterAgent.cmd(agent, {SetAction, %{value: 99}})

      assert agent.state.count == 99
    end

    test "status is :idle when set to 0" do
      agent = CounterAgent.new()
      {agent, _} = CounterAgent.cmd(agent, {SetAction, %{value: 0}})

      assert agent.state.status == :idle
    end
  end

  describe "cmd/2 — action chaining" do
    test "chains multiple actions in a list" do
      agent = CounterAgent.new()

      {agent, _} =
        CounterAgent.cmd(agent, [
          {IncrementAction, %{by: 10}},
          {DecrementAction, %{by: 3}},
          IncrementAction,
          ResetAction,
          {SetAction, %{value: 7}}
        ])

      assert agent.state.count == 7
    end
  end
end
