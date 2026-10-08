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
    extensions: [AshAuthentication, AshStorage],
    authorizers: [Ash.Policy.Authorizer],
    otp_app: :tcm_edu,
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

    attribute :phone, :string do
      public?(true)
    end

    attribute :bio, :string do
      public?(true)
      description("教师/管理员个人简介")
    end

    attribute :job_title, :string do
      public?(true)
      description("教师职称（教授、副教授、讲师…）")
    end

    attribute :school, :string do
      public?(true)
      description("所属学校/机构")
    end

    attribute :major, :string do
      public?(true)
      description("学生专业")
    end

    attribute :student_no, :string do
      public?(true)
      description("学生学号")
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

  relationships do
    belongs_to :class_group, TcmEdu.Classes.ClassGroup do
      allow_nil?(true)
      public?(true)
    end
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
      filter(expr(role == :tenant_admin))
    end

    read :list_teacher_profiles do
      description("公开名师录：本租户教师公开资料（学生端首页，匿名可读）")
      filter(expr(role == :teacher and status == :active))
    end

    create :register_with_role do
      description("""
      Admin 创建租户内用户。

        * 由超管调用（任意租户，可分配 tenant_admin）或 tenant_admin 调用
          （自己的租户内，仅可分配 teacher / student）
        * 角色必须 ∈ `[:tenant_admin, :teacher, :student]`
      """)

      accept([:email, :name, :phone, :role, :status, :class_group_id])

      argument :password, :string do
        allow_nil?(false)
        sensitive?(true)
        constraints(min_length: 6)
      end

      validate(TcmEdu.Accounts.Validations.RestrictTenantAdminRole)

      validate(fn changeset, _context ->
        password = Ash.Changeset.get_argument(changeset, :password)

        if is_binary(password) and byte_size(password) >= 6 do
          :ok
        else
          {:error, field: :password, message: "must be at least 6 characters"}
        end
      end)

      change(set_context(%{strategy_name: :password}))
      change(AshAuthentication.Strategy.Password.HashPasswordChange, only_when_valid?: true)
    end

    update :update_profile do
      description("用户更新自己的资料（不能改 role/status/hashed_password）")
      require_atomic?(false)
      accept([:name, :phone, :bio, :job_title, :school, :major])
    end

    update :admin_update_user do
      description("管理员编辑用户资料（姓名/联系方式/教师/学生字段/班级）")
      require_atomic?(false)

      accept([
        :name,
        :phone,
        :bio,
        :job_title,
        :school,
        :major,
        :student_no,
        :class_group_id
      ])
    end

    update :update_role do
      description("Admin 改用户角色（提权到 tenant_admin 仅超管）")
      require_atomic?(false)
      accept([])

      argument :role, :atom do
        allow_nil?(false)
        constraints(one_of: [:tenant_admin, :teacher, :student])
      end

      validate(TcmEdu.Accounts.Validations.RestrictTenantAdminRole)
      change(set_attribute(:role, arg(:role)))
    end

    update :update_status do
      description("Admin 启停用用户")
      require_atomic?(false)
      accept([])

      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:active, :disabled])
      end

      change(set_attribute(:status, arg(:status)))
    end

    update :change_password do
      description("用户改自己的密码（需提供当前密码）")
      require_atomic?(false)
      accept([])
      argument(:current_password, :string, sensitive?: true, allow_nil?: false)

      argument(:password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 6]
      )

      argument(:password_confirmation, :string, sensitive?: true, allow_nil?: false)

      # 不用 Ash 内置 confirm / PasswordValidation —— 它们写死英文 message，
      # 改用 validate 块返回中文，让 AshPhoenix.Form.errors/2 直接读出。
      validate(fn changeset, _ctx ->
        current = Ash.Changeset.get_argument(changeset, :current_password)
        hashed = Ash.Changeset.get_data(changeset, :hashed_password)

        if is_binary(current) and Bcrypt.verify_pass(current, hashed) do
          :ok
        else
          {:error, field: :current_password, message: "当前密码不正确"}
        end
      end)

      validate(fn changeset, _ctx ->
        pwd = Ash.Changeset.get_argument(changeset, :password)
        confirm = Ash.Changeset.get_argument(changeset, :password_confirmation)

        if pwd && confirm && pwd == confirm do
          :ok
        else
          {:error, field: :password_confirmation, message: "两次输入不一致"}
        end
      end)

      change({AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password})
    end

    update :reset_password do
      description("超管直接重置用户密码（无需原密码，仅超管可用）")
      require_atomic?(false)
      accept([])

      argument(:password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 6]
      )

      argument(:password_confirmation, :string, sensitive?: true, allow_nil?: false)

      # 不用 Ash 内置 confirm —— 它写死英文 message("confirmation did not match value"),
      # 改用 validate 块返回中文,让 AshPhoenix.Form.errors/2 直接读出。
      validate(fn changeset, _ctx ->
        pwd = Ash.Changeset.get_argument(changeset, :password)
        confirm = Ash.Changeset.get_argument(changeset, :password_confirmation)

        if pwd && confirm && pwd == confirm do
          :ok
        else
          {:error, field: :password_confirmation, message: "两次输入不一致"}
        end
      end)

      change({AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password})
    end
  end

  postgres do
    table("users")
    repo(TcmEdu.Repo)

    references do
      reference(:class_group, on_delete: :nilify)
    end
  end

  storage do
    # 用户头像走项目 OSS（测试环境经 app config 覆盖为 AshStorage.Service.Test）。
    service({TcmEdu.Storage.OSS.Service, []})

    blob_resource(TcmEdu.Storage.Blob)
    attachment_resource(TcmEdu.Storage.UserAttachment)

    # 自动生成 `avatar` 关系、`avatar_url` calculation 与
    # `attach_avatar` / `detach_avatar` / `purge_avatar` action。
    has_one_attached(:avatar)
  end

  policies do
    # AshAuthentication 内部流程（sign_in / token 验证）不走业务鉴权。
    # 注意：公开自助注册已关闭（见下面的 register_with_password policy），
    # 账户只能由超管/管理员在管理端分配，因此 bypass 白名单不含注册动作。
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(
        {Ash.Policy.Check.Action, action: [:sign_in_with_password, :sign_in_with_token]}
      )
    end

    # SuperAdmin 跨租户管理：actor 是 SuperAdmin struct 时全放行。
    # Map.fetch(struct, :__struct__) 可取到模块名，故此 check 可用。
    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # get_by_subject 被 AshAuthentication 用来从 JWT subject 反查用户，需公开
    policy action(:get_by_subject) do
      authorize_if(always())
    end

    # 公开自助注册已关闭：学生/教师/管理员均无注册入口，账户由
    # 超管（分配管理员）与管理员（分配教师/学生）在管理端创建。
    policy action(:register_with_password) do
      forbid_if(always())
    end

    # 列表类：仅 tenant_admin / teacher 可列；student 调 list 会被拒绝。
    # 注意：policy 条件列表是 AND 语义，不能把多个 action 写进同一个 policy，
    # 必须每个 action 独立一个 policy 块。
    policy action(:list_users) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:list_students) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:list_teachers) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:list_admins) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    # 公开名师录：任何人可读（含匿名；仅返回公开资料字段，由前端按需选字段）
    policy action(:list_teacher_profiles) do
      authorize_if(always())
    end

    # 单条读取：admin / teacher 可读任意；student 只能读自己（filter 收敛到单条）
    policy action(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(id == ^actor(:id)))
    end

    # 通用 :update 仅 admin 可用；普通用户必须走 update_profile / change_password，
    # 防止 student 通过默认 update 改自己的 role / status。
    policy action(:update) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    # 自助资料 / 密码：本人或 admin
    policy action(:update_profile) do
      authorize_if(expr(id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:change_password) do
      authorize_if(expr(id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    # 头像附件：本人或 admin（与 update_profile 同权限）
    policy action([:attach_avatar, :detach_avatar, :purge_avatar]) do
      authorize_if(expr(id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    # tenant_admin 创建 / 编辑资料 / 改角色 / 启停 / 删除本租户用户
    policy action(:register_with_role) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:admin_update_user) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:update_role) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:update_status) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    # 未匹配任何 policy 的动作 Ash 默认拒绝，无需显式 deny。
    # 注意：:reset_password 故意不配 policy——仅顶部 SuperAdmin bypass
    # 能放行，租户管理员/教师/学生调用都会被拒绝。
  end
end
