defmodule TcmEdu.Accounts.UserRole do
  @moduledoc """
  Join table linking users to roles.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TcmEdu.Accounts

  postgres do
    table "user_roles"
    repo TcmEdu.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, TcmEdu.Accounts.User, allow_nil?: false
    belongs_to :role, TcmEdu.Accounts.Role, allow_nil?: false
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
