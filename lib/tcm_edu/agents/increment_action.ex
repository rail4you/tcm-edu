defmodule TcmEdu.Agents.IncrementAction do
  @moduledoc """
  Increments the counter by a given amount.
  """

  use Jido.Action,
    name: "increment",
    description: "Increments the counter by a specified amount",
    schema: Zoi.object(%{
      by: Zoi.integer() |> Zoi.default(1)
    })

  @impl true
  def run(params, context) do
    current = Map.get(context.state, :count, 0)
    {:ok, %{count: current + params.by}}
  end
end
