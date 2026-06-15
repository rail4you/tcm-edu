defmodule AshTsDemo.TodoDomain do
  @moduledoc """
  Ash domain hosting the `Todo` resource.

  The `AshTypescript.Rpc` extension is responsible for declaring which
  Ash actions are exposed to the TypeScript client. `mix ash_typescript.codegen`
  walks these declarations and writes the generated client to
  `frontend/lib/generated/ash_rpc.ts`.
  """

  use Ash.Domain,
    otp_app: :ash_ts_demo,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTsDemo.Todo do
      rpc_action(:list_todos, :read)
      rpc_action(:get_todo, :read, get?: true)
      rpc_action(:create_todo, :create)
      rpc_action(:update_todo, :update)
      rpc_action(:delete_todo, :destroy)
    end
  end

  resources do
    resource(AshTsDemo.Todo)
  end
end
