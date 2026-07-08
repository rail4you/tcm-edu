defmodule AshTsDemo.Accounts do
  @moduledoc """
  Ash domain hosting authentication resources (User, Token) and RBAC
  resources (Role, Permission, and join tables).
  """

  use Ash.Domain,
    otp_app: :ash_ts_demo,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTsDemo.Accounts.User do
      rpc_action(:list_users, :list_users)
      rpc_action(:register_with_role, :register_with_role)
      rpc_action(:update_role, :update_role)
      rpc_action(:manage_permissions, :manage_permissions)
    end

    resource AshTsDemo.Accounts.Role do
      rpc_action(:list_roles, :read)
      rpc_action(:create_role, :create)
    end

    resource AshTsDemo.Accounts.Permission do
      rpc_action(:list_permissions, :read)
    end
  end

  resources do
    resource AshTsDemo.Accounts.User
    resource AshTsDemo.Accounts.Token
    resource AshTsDemo.Accounts.Role
    resource AshTsDemo.Accounts.Permission
    resource AshTsDemo.Accounts.RolePermission
    resource AshTsDemo.Accounts.UserRole
    resource AshTsDemo.Accounts.UserPermission
  end

  @doc """
  Returns `true` if the user (by id) has the given permission through
  either their role(s) or a direct `UserPermission` grant.

  Used by `AshTsDemo.Checks.HasPermission` at policy evaluation time.
  """
  @spec effective_permissions?(user_id :: String.t(), permission_name :: String.t()) :: boolean
  def effective_permissions?(user_id, permission_name) do
    import Ecto.Query

    role_has? =
      AshTsDemo.Repo.exists?(
        from rp in {"role_permissions", AshTsDemo.Accounts.RolePermission},
          join: ur in {"user_roles", AshTsDemo.Accounts.UserRole},
            on: ur.role_id == rp.role_id,
          join: p in {"permissions", AshTsDemo.Accounts.Permission},
            on: p.id == rp.permission_id,
          where: ur.user_id == ^user_id and p.name == ^permission_name
      )

    role_has? ||
      AshTsDemo.Repo.exists?(
        from up in {"user_permissions", AshTsDemo.Accounts.UserPermission},
          join: p in {"permissions", AshTsDemo.Accounts.Permission},
            on: p.id == up.permission_id,
          where: up.user_id == ^user_id and p.name == ^permission_name
      )
  end

  @doc """
  Returns all effective permission names for a user (union of role-based
  and direct grants).
  """
  @spec effective_permissions(user_id :: String.t()) :: [String.t()]
  def effective_permissions(user_id) do
    import Ecto.Query

    role_perms =
      AshTsDemo.Repo.all(
        from rp in {"role_permissions", AshTsDemo.Accounts.RolePermission},
          join: ur in {"user_roles", AshTsDemo.Accounts.UserRole},
            on: ur.role_id == rp.role_id,
          join: p in {"permissions", AshTsDemo.Accounts.Permission},
            on: p.id == rp.permission_id,
          where: ur.user_id == ^user_id,
          select: p.name
      )

    direct_perms =
      AshTsDemo.Repo.all(
        from up in {"user_permissions", AshTsDemo.Accounts.UserPermission},
          join: p in {"permissions", AshTsDemo.Accounts.Permission},
            on: p.id == up.permission_id,
          where: up.user_id == ^user_id,
          select: p.name
      )

    Enum.uniq(role_perms ++ direct_perms)
  end
end
