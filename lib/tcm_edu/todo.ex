defmodule TcmEdu.Todo do
  @moduledoc """
  Simple Todo resource.

  All actions are permitted (`authorize_if always()`) — adjust the policies
  block once you wire up authentication.
  """

  use Ash.Resource,
    otp_app: :tcm_edu,
    domain: TcmEdu.TodoDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("todos")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 200, trim?: true)
    end

    attribute :completed, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:title, :completed])
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:title, :completed])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_present())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_present())
    end
  end
end
