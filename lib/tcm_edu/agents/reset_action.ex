defmodule TcmEdu.Agents.ResetAction do
  use Jido.Action,
    name: "reset",
    description: "Resets the counter to zero"

  @impl true
  def run(_params, _context) do
    {:ok, %{count: 0}}
  end
end
