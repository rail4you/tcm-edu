defmodule TcmEduWeb.AdminTenantAdminsTest do
  @moduledoc """
  Covers per-tenant admin management (PhoenixTest):

    * super admin creates a tenant_admin from `/admin/users`
    * `/admin/tenants` links each tenant to its (preselected) user management
    * tenant_admin only sees teacher/student roles, but can create teachers
    * backend refuses tenant_admin role grants from non-super-admin actors
      (`register_with_role` and `update_role`)
    * role filter narrows the user table
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.SuperAdmin

  @tenant "tenant_default"

  setup %{conn: conn} do
    super_admin =
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{
          email: "tenant-admins-super-#{System.unique_integer([:positive])}@example.com",
          name: "Tenant Admins Super",
          password: "password123"
        },
        authorize?: false
      )
      |> Ash.create!()

    tenant_admin =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "tenant-admins-ta-#{System.unique_integer([:positive])}@example.com",
          name: "Tenant Admin",
          password: "password123",
          role: :tenant_admin
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    super_conn =
      conn
      |> Plug.Test.init_test_session(%{
        "admin_id" => super_admin.id,
        "admin_role" => "super_admin",
        "admin_tenant" => "public",
        "admin_email" => to_string(super_admin.email),
        "admin_name" => "Tenant Admins Super"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    tenant_conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "admin_id" => tenant_admin.id,
        "admin_role" => "tenant_admin",
        "admin_tenant" => @tenant,
        "admin_email" => to_string(tenant_admin.email),
        "admin_name" => "Tenant Admin"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok,
     super_conn: super_conn,
     tenant_conn: tenant_conn,
     super_admin: super_admin,
     tenant_admin: tenant_admin}
  end

  test "super admin creates a tenant_admin for the tenant", %{super_conn: conn} do
    email = "new-ta-#{System.unique_integer([:positive])}@example.com"

    conn
    |> visit("/admin/users")
    |> click_button("#new-user-btn", "创建用户")
    |> fill_in("邮箱", with: email)
    |> fill_in("姓名", with: "新区管理员")
    |> fill_in("初始密码", with: "password123")
    |> select("角色", option: "租户管理员")
    |> click_button("#create-user-form button[type='submit']", "创建")
    |> assert_has("td", text: email)
    |> assert_has("span", text: "租户管理员")

    assert %User{role: :tenant_admin} =
             User
             |> Ash.Query.filter(email == ^email)
             |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end

  test "tenants page links to the tenant's user management", %{super_conn: conn} do
    conn
    |> visit("/admin/tenants")
    |> assert_has("span", text: "位")
    |> click_link("td a.link", "管理")
    |> open_create_and_assert_tenant(@tenant)
  end

  test "tenant_admin cannot grant tenant_admin, but can create teachers", %{
    tenant_conn: conn,
    tenant_admin: admin
  } do
    email = "new-teacher-#{System.unique_integer([:positive])}@example.com"

    conn
    |> visit("/admin/users")
    |> click_button("#new-user-btn", "创建用户")
    |> refute_has("#create-user-form option", text: "租户管理员")
    |> fill_in("邮箱", with: email)
    |> fill_in("初始密码", with: "password123")
    |> select("角色", option: "教师")
    |> click_button("#create-user-form button[type='submit']", "创建")
    |> assert_has("td", text: email)

    # 后端最终把关：租户管理员直接调 action 也建不出管理员
    assert {:error, %Ash.Error.Invalid{}} =
             User
             |> Ash.Changeset.for_create(
               :register_with_role,
               %{
                 email: "sneaky-#{System.unique_integer([:positive])}@example.com",
                 password: "password123",
                 role: :tenant_admin
               },
               actor: admin,
               tenant: @tenant
             )
             |> Ash.create()
  end

  test "only super admin can promote to tenant_admin", %{
    super_admin: super_admin,
    tenant_admin: admin
  } do
    student =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "promote-#{System.unique_integer([:positive])}@example.com",
          password: "password123",
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    # 注意：actor 必须设在 changeset 上（Ash 规范），传在 Ash.update 调用处时
    # validation 看不到它。
    assert {:error, %Ash.Error.Invalid{}} =
             student
             |> Ash.Changeset.for_update(:update_role, %{role: :tenant_admin}, actor: admin)
             |> Ash.update(tenant: @tenant)

    assert {:ok, %User{role: :tenant_admin}} =
             student
             |> Ash.Changeset.for_update(:update_role, %{role: :tenant_admin}, actor: super_admin)
             |> Ash.update(tenant: @tenant)
  end

  test "role filter narrows the table", %{super_conn: conn, tenant_admin: admin} do
    admin_email = to_string(admin.email)

    conn
    |> visit("/admin/users")
    |> select("按角色筛选", option: "租户管理员")
    |> assert_has("td", text: admin_email)
    |> select("按角色筛选", option: "教师")
    |> refute_has("td", text: admin_email)
    |> select("按角色筛选", option: "全部角色")
    |> assert_has("td", text: admin_email)
  end

  defp open_create_and_assert_tenant(session, tenant) do
    session
    |> click_button("#new-user-btn", "创建用户")
    |> assert_has("code", text: tenant)
  end
end
