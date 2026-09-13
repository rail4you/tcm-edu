defmodule TcmEdu.System.SuperAdmin do
  @moduledoc """
  超级管理员资源。**仅** 存在于 `public` schema（`public.super_admins`）。

  与 `TcmEdu.Accounts.User`（租户内用户）的区别：

    * SuperAdmin 不属于任何租户，能跨租户管理平台
    * 登录后 JWT 中 `tenant: "public"`、`role: "super_admin"`
    * 不能通过 AshAuthentication 的 `auth_routes` 登录（路径特殊）
    * 不能创建租户外的业务资源

  密码策略：

    * 注册时强制 Bcrypt hash
    * 登录时 `sign_in_with_password` 自定义 action 校验 + 返回 JWT
    * `store_all_tokens? false`（不需要 logout-everywhere，超管 token 不入库）
  """

  use Ash.Resource,
    domain: TcmEdu.System,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  require Logger

  postgres do
    table "super_admins"
    repo TcmEdu.Repo
  end

  typescript do
    type_name "SuperAdmin"
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :last_login_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
  end

  code_interface do
    define :register_super_admin, action: :register
    define :super_admin_sign_in, action: :sign_in_with_password
    define :list_super_admins, action: :read
    define :get_super_admin, action: :read, get_by: [:id]
    define :get_super_admin_by_email, action: :read, get_by: [:email]
    define :delete_super_admin, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description """
      通过 RPC 注册超管。

      仅在部署初期通过 `mix tcm_edu.seed_super_admin` 或控制台调用，
      业务 UI 上不暴露注册入口（避免超管账号被滥建）。
      """

      accept [:email, :name]
      argument :password, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 6
      end

      validate fn changeset, _context ->
        password = Ash.Changeset.get_argument(changeset, :password)

        if is_binary(password) and byte_size(password) >= 6 do
          :ok
        else
          {:error, field: :password, message: "must be at least 6 characters"}
        end
      end

      change fn changeset, _context ->
        password = Ash.Changeset.get_argument(changeset, :password)
        hashed = Bcrypt.hash_pwd_salt(password)
        Ash.Changeset.force_change_attribute(changeset, :hashed_password, hashed)
      end,
      only_when_valid?: true
    end

    action :sign_in_with_password, :map do
      argument :email, :string do
        allow_nil? false
      end

      argument :password, :string do
        allow_nil? false
        sensitive? true
      end

      run fn input, _context ->
        # NOTE: `__MODULE__` inside the action run block is the auto-generated
        # action module, not the resource. Use the fully-qualified resource name.
        require Ash.Query
        query = Ash.Query.filter(TcmEdu.System.SuperAdmin, email == ^input.arguments.email)

        case Ash.read(query, authorize?: false) do
          {:ok, [admin]} ->
            if Bcrypt.verify_pass(input.arguments.password, admin.hashed_password) do
              # 更新最后登录时间（冝余保护：未来可加 Oban 队列）
              _ =
                admin
                |> Ash.Changeset.for_update(:touch_last_login, %{})
                |> Ash.update(authorize?: false)

              # 生成带 tenant="public" / role="super_admin" 的 JWT
              case TcmEduWeb.AuthToken.generate(admin.id, %{
                     "tenant" => "public",
                     "role" => "super_admin"
                   }) do
                {:ok, token, _claims} ->
                  {:ok, %{admin: admin, token: token}}

                error ->
                  Logger.error("Failed to generate super admin token: #{inspect(error)}")
                  {:error, :token_generation_failed}
              end
            else
              {:error, :invalid_credentials}
            end

          {:ok, _} ->
            {:error, :invalid_credentials}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    update :touch_last_login do
      accept []
      require_atomic? false
      change set_attribute(:last_login_at, &DateTime.utc_now/0)
    end
  end

  policies do
    # 默认全开：超管资源后续需要 self-bypass 策略再收紧
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end
end