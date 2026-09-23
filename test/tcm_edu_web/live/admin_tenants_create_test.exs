defmodule TcmEduWeb.AdminTenantsCreateTest do
  @moduledoc """
  Regression coverage for tenant creation at `/admin/tenants` (PhoenixTest).

  Guards against the "click 创建 and nothing happens" bug: the create form
  is backed by a hand-rolled Ecto changeset, which must carry `:action`
  (else `to_form/2` drops every error and an invalid submit leaves the
  modal open with zero feedback).
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.System.Organization
  alias TcmEdu.System.SuperAdmin

  setup %{conn: conn} do
    admin =
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{
          email: "tenant-create-#{System.unique_integer([:positive])}@example.com",
          name: "Tenant Create Test",
          password: "password123"
        },
        authorize?: false
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "admin_id" => admin.id,
        "admin_role" => "super_admin",
        "admin_tenant" => "public",
        "admin_email" => to_string(admin.email),
        "admin_name" => "Tenant Create Test"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn}
  end

  test "invalid slug keeps the modal open and shows the error", %{conn: conn} do
    # 2 chars < 3-char minimum, so the submit is rejected server-side and
    # nothing is persisted.
    slug = "gz"

    conn
    |> visit("/admin/tenants")
    |> click_button("#new-tenant-btn", "创建租户")
    |> fill_in("机构名称", with: "测试学院")
    |> fill_in("Slug（作为 schema 后缀，不可更改）", with: slug)
    |> click_button("#create-tenant-form button[type='submit']", "创建")
    |> assert_has("#create-tenant-form")
    |> assert_has("p", text: "小写字母/数字/连字符")

    assert Organization
           |> Ash.Query.filter(slug == ^slug)
           |> Ash.read!(authorize?: false) == []
  end

  test "blank optional email is not flagged while slug error shows", %{conn: conn} do
    conn
    |> visit("/admin/tenants")
    |> click_button("#new-tenant-btn", "创建租户")
    |> fill_in("机构名称", with: "测试学院")
    |> fill_in("Slug（作为 schema 后缀，不可更改）", with: "x")
    |> click_button("#create-tenant-form button[type='submit']", "创建")
    |> assert_has("p", text: "小写字母/数字/连字符")
    |> refute_has("p", text: "邮箱格式不正确")
  end
end
