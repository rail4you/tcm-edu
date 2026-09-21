defmodule TcmEdu.Agents.SetAction do
  use Jido.Action,
    name: "set",
    description: "Sets the counter to a specific value",
    schema:
      Zoi.object(%{
        value: Zoi.integer()
      })

  @impl true
  def run(params, _context) do
    {:ok, %{count: params.value}}
  end
end
