defmodule TcmEdu.System.ApiKeyConfig do
  @moduledoc """
  AI Provider API Key 配置（public schema，跨租户）。

  沿用 kg-edu 的做法：把大模型 key 存进数据库，super admin 可运行时修改，
  无需重启服务。避免把密钥写死在 `config/` 或 `.env`。

  ## 约定

    * `provider`  — 唯一，如 `qwen` / `dashscope` / `deepseek`
    * `api_key`   — 对应 provider 的 key
    * `base_url`  — OpenAI 兼容网关地址（可选，默认走 provider 默认）

  首次启动时若能读到 `~/.pi/agent/models.json`，会 seed 一份（见应用启动
  时的引导逻辑）。
  """

  use Ash.Resource,
    domain: TcmEdu.System,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("api_key_configs")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("ApiKeyConfig")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :provider, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:qwen, :dashscope, :deepseek])
      description("AI provider 标识")
    end

    attribute :api_key, :string do
      allow_nil?(false)
      sensitive?(true)
      description("API Key（敏感，不通过 RPC 明文回传）")
    end

    attribute :base_url, :string do
      public?(true)
      description("OpenAI 兼容网关地址")
    end

    attribute :model, :string do
      public?(true)
      description("默认模型（如 qwen3.8-flash），可为 nil 走系统默认")
    end

    attribute :is_active, :boolean do
      default(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_provider, [:provider])
  end

  code_interface do
    define(:list_api_key_configs, action: :read)
    define(:get_api_key_config, action: :read, get_by: [:provider])
    define(:set_api_key_config, action: :upsert)
    define(:delete_api_key_config, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :upsert do
      primary?(true)
      description("创建或按 provider 更新 key")
      upsert?(true)
      upsert_identity(:unique_provider)
      accept([:provider, :api_key, :base_url, :model, :is_active])
    end

    update :update do
      primary?(true)
      accept([:api_key, :base_url, :model, :is_active])
    end

    read :masked do
      description("读取（api_key 掩码为 sk-****，供管理端展示已配置）")
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # key 值敏感：默认拒绝普通 RPC 明文读取，超管可读（仍建议掩码）
    policy action_type([:create, :destroy]) do
      authorize_if(actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin))
    end

    policy action_type([:read, :update]) do
      authorize_if(actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin))
    end
  end
end
