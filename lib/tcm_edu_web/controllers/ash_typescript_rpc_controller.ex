defmodule TcmEduWeb.AshTypescriptRpcController do
  @moduledoc """
  Thin Phoenix controller that delegates JSON-RPC style calls to AshTypescript.

  Two endpoints are exposed (mounted under `/api/rpc/` in the router):

    * `POST /api/rpc/run`      — execute an RPC action and return the result
    * `POST /api/rpc/validate` — validate input/changeset without persisting

  The body of each request is a JSON object emitted by the generated
  TypeScript client (`frontend/lib/generated/ash_rpc.ts`). AshTypescript's
  pipeline takes care of parameter parsing, field selection, filters, etc.
  """

  use TcmEduWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:tcm_edu, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:tcm_edu, conn, params)
    json(conn, result)
  end
end
