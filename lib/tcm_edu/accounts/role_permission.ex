defmodule TcmEdu.Accounts.RolePermission do
  @moduledoc """
  Join table linking roles to permissions.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TcmEdu.Accounts

  postgres do
    table "role_permissions"
    repo TcmEdu.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :role, TcmEdu.Accounts.Role, allow_nil?: false
    belongs_to :permission, TcmEdu.Accounts.Permission, allow_nil?: false
  end

  identities do
    identity :unique_role_permission, [:role_id, :permission_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:role_id, :permission_id]
    end
  end
end
