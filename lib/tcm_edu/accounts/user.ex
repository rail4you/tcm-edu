defmodule TcmEdu.Accounts.User do
  @moduledoc """
  租户域用户资源。每个租户都有自己的 `users` 表（schema 多租户）。

  ## 多租户策略

  `multitenancy :context` — 由请求上下文（`tenant` claim）决定查询哪个 schema。
  Ash 调用时需传 `tenant: "tenant_<slug>"`。

  ## 角色

  与系统级 SuperAdmin 不同，本资源仅用于租户内的用户：

    * `:tenant_admin`  — 租户管理员
    * `:teacher`       — 教师
    * `:student`       — 学生（默认）

  SuperAdmin 存在 `public.super_admins`，独立处理（。

  ## 迁移路径

  Phase 3 后所有 `Users` 数据从 `public.users` 迁移到 `tenant_default.users`。
  后续新建租户时由 `priv/repo/tenant_migrations/` 中的迁移自动建表。

  ## 与 AshAuthentication

  使用 AshAuthentication 的 password strategy + tokens。
  Token 仍存放在 `public.tokens`（单 schema），不做多租户改造。
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication, AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer],
    domain: TcmEdu.Accounts

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      public?(true)
    end

    attribute :avatar_url, :string do
      public?(true)
    end

    attribute :phone, :string do
      public?(true)
    end

    attribute :bio, :string do
      public?(true)
      description "教师/管理员个人简介"
    end

    attribute :job_title, :string do
      public?(true)
      description "教师职称（教授、副教授、讲师…）"
    end

    attribute :school, :string do
      public?(true)
      description "所属学校/机构"
    end

    attribute :major, :string do
      public?(true)
      description "学生专业"
    end

    attribute :hashed_password, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(false)
    end

    attribute :role, :atom do
      allow_nil?(false)
      default(:student)
      public?(true)
      constraints(one_of: [:tenant_admin, :teacher, :student])
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:active)
      public?(true)
      constraints(one_of: [:active, :disabled])
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_email_per_tenant, [:email])
  end

  authentication do
    strategies do
      password :password do
        identity_field(:email)
      end
    end

    tokens do
      enabled?(true)
      token_resource(TcmEdu.Accounts.Token)
      store_all_tokens?(true)
      require_token_presence_for_authentication?(true)

      signing_secret(fn _, _ ->
        {:ok, Application.fetch_env!(:tcm_edu, :token_signing_secret)}
      end)
    end
  end

  actions do
    defaults([:read, :update, :destroy])

    read :get_by_subject do
      description("Get a user by the subject claim in a JWT")
      argument(:subject, :string, allow_nil?: false)
      get?(true)
      prepare(AshAuthentication.Preparations.FilterBySubject)
    end

    read :list_users do
      description("List all users in the current tenant (admin only)")
    end

    read :list_students do
      description("List students in the current tenant (admin/teacher)")
      filter(expr(role == :student))
    end

    read :list_teachers do
      description("List teachers in the current tenant (admin)")
      filter(expr(role == :teacher))
    end

    read :list_admins do
      description("List tenant admins in the current tenant (super_admin)")
      filter expr(role == :tenant_admin)
    end

    create :register_with_role do
      description """
      Admin 创建租户内用户。

        * 由 tenant_admin 调用（在自己的租户内）或 super_admin 调用
        * 角色必须 ∈ `[:tenant_admin, :teacher, :student]`
      """

      accept([:email, :name, :phone, :avatar_url, :role, :status])

      argument :password, :string do
        allow_nil?(false)
        sensitive?(true)
        constraints(min_length: 8)
      end

      validate fn changeset, _context ->
        password = Ash.Changeset.get_argument(changeset, :password)

        if is_binary(password) and byte_size(password) >= 8 do
          :ok
        else
          {:error, field: :password, message: "must be at least 8 characters"}
        end
      end

      change(set_context(%{strategy_name: :password}))
      change(AshAuthentication.Strategy.Password.HashPasswordChange, only_when_valid?: true)
    end

    update :update_profile do
      description "用户更新自己的资料（不能改 role/status/hashed_password）"
      require_atomic?(false)
      accept([:name, :avatar_url, :phone, :bio, :job_title, :school, :major])
    end

    update :update_role do
      description "Admin 改用户角色"
      require_atomic?(false)
      accept([])
      argument :role, :atom do
        allow_nil?(false)
        constraints(one_of: [:tenant_admin, :teacher, :student])
      end
      change(set_attribute(:role, arg(:role)))
    end

    update :update_status do
      description "Admin 启停用用户"
      require_atomic?(false)
      accept([])
      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:active, :disabled])
      end
      change(set_attribute(:status, arg(:status)))
    end

    update :change_password do
      description "用户改自己的密码（需提供当前密码）"
      require_atomic?(false)
      accept([])
      argument :current_password, :string, sensitive?: true, allow_nil?: false
      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]
      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)
      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}
      change({AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password})
    end
  end

  postgres do
    table("users")
    repo(TcmEdu.Repo)
  end

  policies do
    # AshAuthentication 内部流程（sign_in / register / token 验证）不走业务鉴权
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # SuperAdmin 跨租户管理：actor 是 SuperAdmin struct 时全放行。
    # Map.fetch(struct, :__struct__) 可取到模块名，故此 check 可用。
    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if always()
    end

    # get_by_subject 被 AshAuthentication 用来从 JWT subject 反查用户，需公开
    policy action(:get_by_subject) do
      authorize_if always()
    end

    # 列表类：仅 tenant_admin / teacher 可列；student 调 list 会被拒绝。
    # 注意：policy 条件列表是 AND 语义，不能把多个 action 写进同一个 policy，
    # 必须每个 action 独立一个 policy 块。
    policy action(:list_users) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if actor_attribute_equals(:role, :teacher)
    end

    policy action(:list_students) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if actor_attribute_equals(:role, :teacher)
    end

    policy action(:list_teachers) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if actor_attribute_equals(:role, :teacher)
    end

    policy action(:list_admins) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    # 单条读取：admin / teacher 可读任意；student 只能读自己（filter 收敛到单条）
    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if actor_attribute_equals(:role, :teacher)
      authorize_if expr(id == ^actor(:id))
    end

    # 通用 :update 仅 admin 可用；普通用户必须走 update_profile / change_password，
    # 防止 student 通过默认 update 改自己的 role / status。
    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    # 自助资料 / 密码：本人或 admin
    policy action(:update_profile) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy action(:change_password) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    # tenant_admin 创建 / 改角色 / 启停 / 删除本租户用户
    policy action(:register_with_role) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy action(:update_role) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy action(:update_status) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end
    # 未匹配任何 policy 的动作 Ash 默认拒绝，无需显式 deny。
  end

  typescript do
    type_name("User")
  end
end