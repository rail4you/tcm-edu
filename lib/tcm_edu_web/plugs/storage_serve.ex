defmodule TcmEduWeb.Plugs.StorageServe do
  @moduledoc """
  Wraps `AshStorage.Plug.DiskServe` for use in the Phoenix Endpoint.

  The DiskServe plug expects to be mounted via `forward "/storage", ...` but
  Phoenix Endpoints only support `plug/2`. This wrapper intercepts requests
  under `/storage/` and delegates them to DiskServe.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: AshStorage.Plug.DiskServe.init(opts)

  @impl true
  def call(%{path_info: ["storage" | rest]} = conn, opts) do
    conn
    |> Map.put(:path_info, rest)
    |> AshStorage.Plug.DiskServe.call(opts)
  end

  def call(conn, _opts), do: conn
end
