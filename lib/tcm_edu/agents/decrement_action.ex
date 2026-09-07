defmodule TcmEdu.Agents.DecrementAction do
  use Jido.Action,
    name: "decrement",
    description: "Decrements the counter by a specified amount",
    schema: Zoi.object(%{
      by: Zoi.integer() |> Zoi.default(1)
    })

  @impl true
  def run(params, context) do
    current = Map.get(context.state, :count, 0)
    {:ok, %{count: current - params.by}}
  end
end
