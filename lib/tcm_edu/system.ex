defmodule TcmEdu.System do
  @moduledoc """
  系统域：管理跨租户的资源。

  包含：
    * `TcmEdu.System.Organization` — 租户元数据（public schema）
    * `TcmEdu.System.SuperAdmin`   — 超级管理员（public schema）
    * `TcmEdu.System.AuditLog`     — 操作日志（public schema）
    * `TcmEdu.System.ApiKeyConfig` — AI Provider Key 配置（public schema）
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.System.Organization do
      rpc_action(:list_organizations, :read)
      rpc_action(:get_organization, :read, get_by: [:id])
      rpc_action(:create_organization, :create_with_schema)
      rpc_action(:update_organization, :update_details)
      rpc_action(:archive_organization, :archive)
      rpc_action(:suspend_organization, :suspend)
      rpc_action(:activate_organization, :activate)
      rpc_action(:delete_organization, :destroy)
    end

    resource TcmEdu.System.SuperAdmin do
      rpc_action(:list_super_admins, :read)
      rpc_action(:register_super_admin, :register)
      rpc_action(:super_admin_sign_in, :sign_in_with_password)
    end

    resource TcmEdu.System.AuditLog do
      rpc_action(:list_audit_logs, :read)
      rpc_action(:list_filtered_audit_logs, :filtered)
      rpc_action(:record_audit_log, :record)
    end

    resource TcmEdu.System.ApiKeyConfig do
      rpc_action(:list_api_key_configs, :read)
      rpc_action(:get_api_key_config, :read, get_by: [:provider])
      rpc_action(:set_api_key_config, :upsert)
      rpc_action(:delete_api_key_config, :destroy)
    end
  end

  resources do
    resource TcmEdu.System.Organization
    resource TcmEdu.System.SuperAdmin
    resource TcmEdu.System.AuditLog
    resource TcmEdu.System.ApiKeyConfig
  end
end
