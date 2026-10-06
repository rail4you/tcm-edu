defmodule TcmEduWeb.Plugs.SetTenantForSignIn do
  @moduledoc """
  从请求 body 提取 `organization_slug`，定位对应 Organization，得到 `schema_name`，
  通过 `Ash.PlugHelpers.set_tenant/2` 写入 `conn.private[:ash][:tenant]`。

  ## 用法

  只挂到 `:api` pipeline（sign-in / sign-up 路由），**不**挂到 `:api_auth`。
  顺序：

      plug :accepts, ["json"]
      plug TcmEduWeb.Plugs.SetTenantForSignIn
      plug CORSPlug, ...
      ... auth_routes ...

  ## 默认行为

    * body 含 `organization_slug` → 查 Org 得到 `schema_name` → 设置 tenant
    * body **不含** `organization_slug`（旧调用） → fallback 到 `"tenant_default"`
    * body slug 无效 → fallback 到 `"tenant_default"`
  """

  alias TcmEdu.System.Organization

  @default_tenant "tenant_default"

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_organization_slug(conn) do
      {:ok, slug} ->
        Ash.PlugHelpers.set_tenant(conn, tenant_for_slug(slug))

      :no_slug ->
        # 没指定 organization_slug → 默认 tenant_default
        Ash.PlugHelpers.set_tenant(conn, @default_tenant)
    end
  end

  defp extract_organization_slug(conn) do
    case conn.body_params do
      %{"organization_slug" => slug} when is_binary(slug) and slug != "" ->
        {:ok, slug}

      %{"user" => %{"organization_slug" => slug}} when is_binary(slug) and slug != "" ->
        {:ok, slug}

      _ ->
        :no_slug
    end
  end

  defp tenant_for_slug(slug) do
    # Ash.get/3：第 2 个参数是 id/filter，第 3 个才是 opts。写成
    # Ash.get(Organization, slug: slug, authorize?: false) 会把整个列表当 id，
    # 导致 authorize?: false 被忽略、policy 拒绝 → 永远回退 tenant_default。
    case Ash.get(Organization, [slug: slug], authorize?: false) do
      {:ok, %Organization{schema_name: schema_name}} -> schema_name
      _ -> @default_tenant
    end
  end
end
