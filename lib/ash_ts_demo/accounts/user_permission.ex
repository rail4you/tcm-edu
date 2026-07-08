defmodule AshTsDemo.Accounts.UserPermission do
  @moduledoc """
  Direct permission grants to individual users (overrides/additions to role-based permissions).
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: AshTsDemo.Accounts

  postgres do
    table "user_permissions"
    repo AshTsDemo.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, AshTsDemo.Accounts.User, allow_nil?: false
    belongs_to :permission, AshTsDemo.Accounts.Permission, allow_nil?: false
  end

  identities do
    identity :unique_user_permission, [:user_id, :permission_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :permission_id]
    end
  end
end
