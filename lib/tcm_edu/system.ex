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
    extensions: [AshPhoenix]

  resources do
    resource TcmEdu.System.Organization
    resource TcmEdu.System.SuperAdmin
    resource TcmEdu.System.AuditLog
    resource TcmEdu.System.ApiKeyConfig
  end
end
