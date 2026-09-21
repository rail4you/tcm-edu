defmodule TcmEduWeb.AdminKnowledgeLiveTest do
  @moduledoc """
  E2E for the admin knowledge-base audit view (`/admin/knowledge`):

    * super admin sees tenant selector + metric cards + source table
    * tenant docs render with status and switches
    * preview modal opens for a source
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Knowledge.TenantDoc
  alias TcmEdu.System.SuperAdmin

  @tenant "tenant_default"

  setup %{conn: conn} do
    admin =
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{
          email: "admin-kb-#{System.unique_integer([:positive])}@example.com",
          name: "KB Admin",
          password: "password123"
        },
        authorize?: false
      )
      |> Ash.create!()

    # 造一篇已向量化的知识库文档
    {:ok, _doc} =
      TenantDoc.create_tenant_doc(
        %{
          title: "2025 中医基础教学大纲",
          doc_type: :syllabus,
          content: "第一章 阴阳学说",
          source_name: "outline.docx"
        },
        tenant: @tenant,
        authorize?: false
      )

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "admin_id" => admin.id,
        "admin_role" => "super_admin",
        "admin_tenant" => "public",
        "admin_email" => to_string(admin.email),
        "admin_name" => "KB Admin"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, admin: admin}
  end

  test "super admin sees tenant selector, metrics and the source table", %{conn: conn} do
    conn
    |> visit("/admin/knowledge")
    |> assert_has("p", "知识库")
    |> assert_has("#tenant-select")
    |> assert_has("p", "资料源")
    |> assert_has("p", "已向量化")
    |> assert_has("p", "处理中")
    |> assert_has("p", "失败")
    |> assert_has("td", "2025 中医基础教学大纲")
    |> assert_has("td", "outline.docx")
  end

  test "preview modal shows document text", %{conn: conn} do
    conn
    |> visit("/admin/knowledge")
    |> assert_has("td", "outline.docx")
    |> click_button("#preview-outline\\.docx", "预览")
    |> assert_has("pre", "第一章 阴阳学说")
    |> click_button("关闭")
    |> refute_has("pre", "第一章 阴阳学说")
  end
end
