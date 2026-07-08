defmodule AshTsDemo.Accounts.UserRole do
  @moduledoc """
  Join table linking users to roles.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: AshTsDemo.Accounts

  postgres do
    table "user_roles"
    repo AshTsDemo.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, AshTsDemo.Accounts.User, allow_nil?: false
    belongs_to :role, AshTsDemo.Accounts.Role, allow_nil?: false
  end

  identities do
    identity :unique_user_role, [:user_id, :role_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :role_id]
    end
  end
end
