defmodule TcmEdu.Agents.MultiplyAction do
  @moduledoc """
  Multiplies two numbers. Used as a tool by AI agents.
  """

  use Jido.Action,
    name: "multiply",
    description: "Multiplies two numbers together",
    schema: Zoi.object(%{
      a: Zoi.float(),
      b: Zoi.float()
    })

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{result: a * b}}
  end
end
