defmodule TcmEdu.Agents.CounterAgent do
  @moduledoc """
  A simple counter agent that demonstrates the Jido agent pattern.

  State:
    - `count` — current counter value (integer, default 0)
    - `status` — :idle | :counting | :done (atom, default :idle)

  Actions:
    - `IncrementAction` — adds to count
    - `DecrementAction` — subtracts from count
    - `ResetAction` — resets count to 0
    - `SetAction` — sets count to a specific value
  """

  use Jido.Agent,
    name: "counter_agent",
    description: "Tracks a configurable counter with increment, decrement, reset, and set",
    schema: [
      count: [type: :integer, default: 0],
      status: [type: :atom, default: :idle]
    ]
end
