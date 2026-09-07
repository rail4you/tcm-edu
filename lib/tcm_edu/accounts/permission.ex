defmodule TcmEdu.Accounts.Permission do
  @moduledoc """
  A single permission (e.g. "post:create", "post:update").
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    domain: TcmEdu.Accounts

  postgres do
    table "permissions"
    repo TcmEdu.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z_]+:[a-z_]+$/
    end

    attribute :description, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  typescript do
    type_name("Permission")
  end

  identities do
    identity :unique_permission_name, [:name]
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
