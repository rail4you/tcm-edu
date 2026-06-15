defmodule AshTsDemo.Accounts.User do
  @moduledoc """
  User resource with password-based authentication.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer],
    domain: AshTsDemo.Accounts

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      allow_nil?(false)
      public?(true)
    end

    attribute :hashed_password, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(false)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_email, [:email])
  end

  authentication do
    strategies do
      password :password do
        identity_field(:email)
      end
    end

    tokens do
      enabled?(true)
      token_resource(AshTsDemo.Accounts.Token)
      store_all_tokens?(true)
      require_token_presence_for_authentication?(true)

      signing_secret(fn _, _ ->
        {:ok, Application.fetch_env!(:ash_ts_demo, :token_signing_secret)}
      end)
    end
  end

  actions do
    defaults([:read])

    read :get_by_subject do
      description("Get a user by the subject claim in a JWT")
      argument(:subject, :string, allow_nil?: false)
      get?(true)
      prepare(AshAuthentication.Preparations.FilterBySubject)
    end
  end

  postgres do
    table("users")
    repo(AshTsDemo.Repo)
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    policy action(:get_by_subject) do
      authorize_if(always())
    end

    policy always() do
      forbid_if(always())
    end
  end
end
