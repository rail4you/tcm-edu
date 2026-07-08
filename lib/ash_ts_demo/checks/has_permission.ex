defmodule AshTsDemo.Checks.HasPermission do
  @moduledoc """
  A `SimpleCheck` that returns `true` when the actor has the given permission
  through either their role(s) or a direct `UserPermission` grant.

  ## Usage

      policy action_type(:create) do
        authorize_if {AshTsDemo.Checks.HasPermission, permission: "post:create"}
      end
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "user has the required permission"

  @impl true
  def match?(nil, _context, _opts), do: false

  @impl true
  def match?(actor, _context, opts) do
    permission = opts[:permission]
    user_id = actor.id

    AshTsDemo.Accounts.effective_permissions?(user_id, permission)
  end
end
