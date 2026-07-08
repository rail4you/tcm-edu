defmodule AshTsDemo.Accounts.User do
  @moduledoc """
  User resource with password-based authentication and RBAC permissions.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication, AshTypescript.Resource],
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

    attribute :role, :atom do
      allow_nil?(false)
      default(:user)
      public?(true)
      constraints(one_of: [:admin, :user])
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  typescript do
    type_name("User")
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

  relationships do
    has_many :user_roles, AshTsDemo.Accounts.UserRole
    has_many :user_permissions, AshTsDemo.Accounts.UserPermission
  end

  actions do
    defaults([:read])

    read :get_by_subject do
      description("Get a user by the subject claim in a JWT")
      argument(:subject, :string, allow_nil?: false)
      get?(true)
      prepare(AshAuthentication.Preparations.FilterBySubject)
    end

    read :list_users do
      description("List all users (admin only)")
    end

    read :get_user_permissions do
      description("Get a user's effective permissions from RBAC tables (admin only)")
      argument :user_id, :uuid, allow_nil?: false
      get?(true)

      prepare fn query, _ ->
        user_id = Ash.Query.get_argument(query, :user_id)
        perms = AshTsDemo.Accounts.effective_permissions(user_id)
        # Return a map with the permissions
        {:ok, Ash.Query.set_result(query, %{user_id: user_id, permissions: perms})}
      end
    end

    update :update_role do
      description("Update a user's role (admin only)")
      require_atomic?(false)
      accept([])

      argument :role, :atom do
        allow_nil?(false)
        constraints(one_of: [:admin, :user])
      end

      change(set_attribute(:role, arg(:role)))
    end

    update :manage_permissions do
      description("Update a user's granular permissions (admin only)")
      require_atomic?(false)
      accept([])

      argument :permissions, {:array, :string} do
        allow_nil?(false)
        default([])
      end

      change(AshTsDemo.Accounts.Changes.SyncUserPermissions)
    end

    create :register_with_role do
      description("Register a new user with a specific role (admin only)")
      accept([:email, :role])

      argument :password, :string do
        allow_nil?(false)
        sensitive?(true)
      end

      change(set_context(%{strategy_name: :password}))
      change(AshAuthentication.GenerateTokenChange)
      change(AshAuthentication.Strategy.Password.HashPasswordChange)
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

    # Admin can list all users
    policy [action(:list_users), actor_attribute_equals(:role, :admin)] do
      authorize_if(always())
    end

    # Admin can manage roles and permissions
    policy [action(:update_role), actor_attribute_equals(:role, :admin)] do
      authorize_if(always())
    end

    policy [action(:register_with_role), actor_attribute_equals(:role, :admin)] do
      authorize_if(always())
    end

    policy [action(:manage_permissions), actor_attribute_equals(:role, :admin)] do
      authorize_if(always())
    end

    policy action(:read) do
      authorize_if(actor_present())
    end
  end
end
