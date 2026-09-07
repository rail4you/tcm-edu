defmodule TcmEduWeb.Plugs.SetTenantFromToken do
  @moduledoc """
  从 JWT 提取 tenant / role 信息并设置到 `conn.private`，供下游 Ash 调用使用。

  ## 工作机制

    1. 从 `Authorization: Bearer …` 头读 JWT
    2. 验签并解析 claims（用 `TcmEduWeb.AuthToken.verify/1`）
    3. 根据 `tenant` claim 加载 actor：
        * `tenant == "public"`     → 先尝试 SuperAdmin，找不到再回落到 User
        * `tenant == "tenant_<s>"` → 加载对应 schema 的 User（Phase 3 启用）
    4. 设置：
        * `conn.private[:ash_actor]`     — actor 结构体
        * `conn.private[:ash_tenant]`    — tenant 字符串（`public` 或 `tenant_<slug>`）
        * `conn.private[:ash_context]`   — 包含 tenant + actor 的 context map

  ## 失败处理

    解析失败 → 静默继续（请求被当成匿名）。下游 Ash policy 应负责拦截。

  ## 与 AshAuthentication 集成的 plug 的关系

    当前 `:api_auth` pipeline 已经有 `retrieve_from_bearer` + `set_actor`，
    它们也会从 JWT 拿 `sub` 并设置 actor。本 plug 是它们的**叠加**：
    在 `set_actor` 之后执行，覆盖 Ash context 的 tenant 字段。
  """

  import Plug.Conn
  require Logger

  alias TcmEduWeb.AuthToken
  alias TcmEdu.System.SuperAdmin
  alias TcmEdu.Accounts.User

  @public_tenant "public"
  @default_tenant "tenant_default"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> apply_token()
    |> ensure_tenant()
  end

  # 无 token（匿名）或解析失败时回退到默认租户，保证学生端公开浏览可用。
  # 已通过 JWT 设置了 tenant 的请求不受影响。
  defp ensure_tenant(conn) do
    case Ash.PlugHelpers.get_tenant(conn) do
      nil -> Ash.PlugHelpers.set_tenant(conn, @default_tenant)
      _ -> conn
    end
  end

  defp apply_token(conn) do
    case extract_bearer_token(conn) do
      {:ok, token} ->
        case AuthToken.verify(token) do
          {:ok, claims} ->
            apply_claims(conn, claims)

          {:error, reason} ->
            # 静默失败：让下游 Ash policy 决定是否拒绝
            Logger.debug("SetTenantFromToken: verify failed (#{inspect(reason)})")
            conn
        end

      :no_token ->
        conn
    end
  end

  # ── private ────────────────────────────────────────────────────────

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when byte_size(token) > 0 -> {:ok, token}
      _ -> :no_token
    end
  end

  defp apply_claims(conn, claims) do
    tenant = Map.get(claims, "tenant", @public_tenant)
    role = Map.get(claims, "role", "user")
    subject = Map.get(claims, "sub")

    actor = load_actor(subject, tenant, role)

    case actor do
      {:ok, user_or_admin} ->
        # 用 Ash.PlugHelpers.set_tenant/2 写 conn.private[:ash][:tenant]，
        # 这样 AshTypescript.Rpc 读取时能拿到。
        conn
        |> Ash.PlugHelpers.set_actor(user_or_admin)
        |> Ash.PlugHelpers.set_tenant(tenant)
        |> put_private(:ash_context, %{tenant: tenant, actor: user_or_admin})
        |> put_private(:tcm_edu_role, role)

      :error ->
        conn
    end
  end

  defp load_actor(subject, _tenant, "super_admin") when is_binary(subject) do
    case extract_user_id(subject) do
      {:ok, user_id} ->
        case Ash.get(SuperAdmin, user_id, authorize?: false) do
          {:ok, %SuperAdmin{} = admin} -> {:ok, admin}
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp load_actor(subject, tenant, _role) when is_binary(subject) and is_binary(tenant) do
    case extract_user_id(subject) do
      {:ok, user_id} ->
        # tenant may 可能是 public (Phase 3 后用户都在 tenant_<slug>)
        # 但为了兼容性，public 仍走原表，tenant_<slug> 走多租户表
        case Ash.get(User, user_id, tenant: tenant, authorize?: false) do
          {:ok, %User{} = user} -> {:ok, user}
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp load_actor(_, _, _), do: :error

  defp extract_user_id("user?id=" <> user_id), do: {:ok, user_id}
  defp extract_user_id(_), do: :error
end