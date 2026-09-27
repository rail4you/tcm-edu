defmodule TcmEdu.System.Organization do
  @moduledoc """
  系统级组织（租户）资源。

  每个 Organization 映射到一个独立的 PostgreSQL schema
  （命名规则 `tenant_<slug>`）。所有租户域资源（Users、Courses、...）
  都运行在该 schema 中，由 `Ash.ToTenant` 协议根据当前 actor 的
  `tenant_id` 自动切换 `search_path`。

  ## 关键设计

    * `manage_tenant` 声明 schema 命名模板
    * `create_with_schema` action 在事务内创建 schema 并跑迁移
    * `destroy` action 触发 `DROP SCHEMA … CASCADE`（不可逆！）
    * policies 当前允许所有人调用——权限收口在 Phase 2 的超管体系完成

  ## 字段说明

    * `slug`        URL 安全的短标识，作为 schema 名后缀
    * `schema_name` 由 create 钩子自动计算，等于 `"tenant_" <> slug`
    * `status`      `:active | :suspended | :archived`
    * `plan`        `:free | :pro | :enterprise`（占位字段）
  """

  use Ash.Resource,
    domain: TcmEdu.System,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Logger

  postgres do
    table("organizations")
    repo(TcmEdu.Repo)

    # AshPostgres 用这个块在创建 Organization 时自动 CREATE SCHEMA 并跑
    # tenant 迁移。template 的 `:slug` 来自下面的 attribute。
    manage_tenant do
      template(["tenant_", :slug])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
      description("URL-safe 短标识，作为 schema 名后缀（tenant_<slug>）")
      # 不用 constraints(match:) — 它的错误是英文 "must match the pattern %{regex}",
      # 而业务需要中文提示。改由 :create_with_schema action 上的 validate 块提供。
    end

    attribute :schema_name, :string do
      public?(true)
      description("由 create 钩子自动计算，格式 'tenant_<slug>'")
    end

    attribute :contact_email, :string do
      public?(true)
    end

    attribute :contact_phone, :string do
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :logo_url, :string do
      public?(true)
    end

    attribute :status, :atom do
      default(:active)
      constraints(one_of: [:active, :suspended, :archived])
      public?(true)
    end

    attribute :plan, :atom do
      default(:free)
      constraints(one_of: [:free, :pro, :enterprise])
      public?(true)
    end

    attribute :expires_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  code_interface do
    define(:create_organization, action: :create_with_schema)
    define(:list_organizations, action: :read)
    define(:get_organization, action: :read, get_by: [:id])
    define(:get_organization_by_slug, action: :read, get_by: [:slug])
    define(:update_organization, action: :update)
    define(:archive_organization, action: :archive)
    define(:suspend_organization, action: :suspend)
    define(:activate_organization, action: :activate)
    define(:delete_organization, action: :destroy)
  end

  actions do
    defaults([:read, :update])

    update :update_details do
      description("管理端编辑租户资料（不含 slug / schema_name，创建后不可改）。")
      accept([:name, :contact_email, :contact_phone, :description, :logo_url, :plan, :expires_at])
    end

    create :create_with_schema do
      primary?(true)

      description("""
      创建组织，并在同一事务内 CREATE SCHEMA + 跑租户迁移 + 写入 schema_name。

      行为：
        1. 计算 `schema_name = "tenant_" <> slug`
        2. 调用 `TcmEdu.TenantProvisioning.provision_tenant/2`
           - CREATE SCHEMA IF NOT EXISTS tenant_<slug>
           - 在该 schema 上跑 `priv/repo/tenant_migrations/*.exs`
           - 创建初始 tenant_admin 用户（Phase 3 启用）
        3. 任何一步失败 → 整体回滚
      """)

      accept([
        :name,
        :slug,
        :contact_email,
        :contact_phone,
        :description,
        :logo_url,
        :plan,
        :expires_at
      ])

      # 自定义错误文案,沿用旧 Ecto changeset 的友好提示(否则 Ash 默认输出
      # `must match the pattern %{regex}`,对中文用户不友好)。
      validate(fn changeset, _ctx ->
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        case slug do
          nil ->
            :ok

          slug ->
            if Regex.match?(~r/^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/, slug) do
              :ok
            else
              {:error, field: :slug, message: "小写字母/数字/连字符，3~32 位"}
            end
        end
      end)

      change(fn changeset, _context ->
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        if slug do
          Ash.Changeset.change_attribute(changeset, :schema_name, "tenant_" <> slug)
        else
          changeset
        end
      end)

      change(
        after_action(fn _changeset, organization, _context ->
          case TcmEdu.TenantProvisioning.provision_tenant(organization) do
            :ok ->
              {:ok, organization}

            {:error, reason} = error ->
              Logger.error(
                "TenantProvisioning failed for #{organization.slug}: #{inspect(reason)}"
              )

              error
          end
        end)
      )
    end

    update :archive do
      description("软删除（保留 schema，仅修改状态）")
      accept([])
      change(set_attribute(:status, :archived))
    end

    update :suspend do
      description("暂停租户（用户无法登录，但数据保留）")
      accept([])
      change(set_attribute(:status, :suspended))
    end

    update :activate do
      description("恢复 active 状态")
      accept([])
      change(set_attribute(:status, :active))
    end

    destroy :destroy do
      primary?(true)

      description("""
      硬删除：删除 record 并 `DROP SCHEMA <schema_name> CASCADE`。

      **DESTRUCTIVE**：会删除该租户下所有用户、课程等数据。
      生产环境务必加二次确认。
      """)

      require_atomic?(false)

      change(fn changeset, _context ->
        schema_name = changeset.data.schema_name

        if is_binary(schema_name) and schema_name != "" do
          Logger.warning("Dropping tenant schema: #{schema_name}")

          # 注意：schema 名用双引号包裹，slugs 里的连字符才能被识别为标识符
          TcmEdu.Repo.query("DROP SCHEMA IF EXISTS \"#{schema_name}\" CASCADE")
        end

        changeset
      end)
    end
  end

  policies do
    # SuperAdmin 跨租户运营：actor 是 SuperAdmin struct 时全放行
    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 租户列表对登录用户可见（名称/slug 非敏感；管理端租户选择器需要）
    policy action_type(:read) do
      authorize_if(actor_present())
    end

    # 创建 / 改资料 / 状态流转 / 删除仅超管
    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin))
    end
  end
end
