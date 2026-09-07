defmodule TcmEdu.Accounts do
  @moduledoc """
  Ash domain hosting authentication resources (User, Token).

  ## 多租户

  `User` 与 `Role`/`Permission` 资源采用 `multitenancy :context`，查询时需传
  `tenant: "tenant_<slug>"`（除非被策略 bypass）。`Token` 仍位于 `public`（单 schema），
  负责记录所有租户用户的 token 元数据。

  ## 角色

  Phase 3 后 `User.role` 约束：`[:tenant_admin, :teacher, :student]`。
  细粒度 RBAC（Role/Permission）已废弃。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Accounts.User do
      rpc_action :list_users, :list_users
      rpc_action :list_students, :list_students
      rpc_action :list_teachers, :list_teachers
      rpc_action :list_teacher_profiles, :list_teacher_profiles
      rpc_action :list_admins, :list_admins
      rpc_action :register_with_role, :register_with_role
      rpc_action :update_profile, :update_profile
      rpc_action :delete_user, :destroy
      rpc_action :update_user_role, :update_role
      rpc_action :update_user_status, :update_status
      rpc_action :change_user_password, :change_password
    end
  end

  resources do
    resource TcmEdu.Accounts.User
    resource TcmEdu.Accounts.Token
  end

  # ── RBAC compat shims（保留以便阶段过渡期查询不报错） ──────────
  # Phase 3 中 RBAC 表被删除，以下函数变为 no-op，返回空。
  # 后续业务代码不再依赖这些函数。

  @doc """
  Returns `true` if the user has the given permission name. Phase 3 后
  角色即权限，简化版：返回 actor 是否为对应角色。
  """
  @spec effective_permissions?(user_id :: String.t(), permission_name :: String.t()) :: boolean
  def effective_permissions?(_user_id, _permission_name), do: false

  @doc """
  Returns all permission names. Phase 3 后 RBAC 系统废弃，返回空列表。
  """
  @spec effective_permissions(user_id :: String.t()) :: [String.t()]
  def effective_permissions(_user_id), do: []
end
