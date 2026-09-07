defmodule TcmEdu.Accounts.Role do
  @moduledoc """
  A named role (e.g. "admin", "user") that bundles permissions.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    domain: TcmEdu.Accounts

  postgres do
    table "roles"
    repo TcmEdu.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z_]+$/
    end

    attribute :description, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  typescript do
    type_name("Role")
  end

  identities do
    identity :unique_role_name, [:name]
  end

  relationships do
    many_to_many :permissions, TcmEdu.Accounts.Permission do
      through TcmEdu.Accounts.RolePermission
      source_attribute_on_join_resource :role_id
      destination_attribute_on_join_resource :permission_id
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :description]
    end

    update :update do
      primary? true
      accept [:name, :description]
    end
  end
end
