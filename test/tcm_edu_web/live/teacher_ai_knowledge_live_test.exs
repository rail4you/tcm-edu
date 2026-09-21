defmodule TcmEduWeb.TeacherAIKnowledgeLiveTest do
  @moduledoc """
  E2E coverage for the teacher knowledge base page (`/teacher/ai/knowledge`):

    * uploading an xlsx creates TenantDocs and shows status,
    * uploading an unsupported format shows an error,
    * deleting a source removes its docs from the list.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias Elixlsx.{Sheet, Workbook}
  alias TcmEdu.Accounts.User
  alias TcmEdu.Knowledge.TenantDoc
  alias TcmEdu.Workers.TenantDocEmbeddingWorker

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "knowledge-live-#{System.unique_integer([:positive])}@example.com",
          name: "KB Teacher",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "KB Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher}
  end

  test "teacher uploads an xlsx into the knowledge base", %{conn: conn} do
    path = temp_file("病例库.xlsx", fixture_xlsx())

    conn
    |> visit("/teacher/ai/knowledge")
    |> upload("文件", path, exact: false)
    |> fill_in("资料标题", with: "桂枝汤病例库")
    |> select("资料类型", option: "病例库")
    |> click_button("上传并入库")
    |> assert_has("p", "已入库", exact: false)
    |> assert_has("p", "桂枝汤病例库")
    |> assert_has("p", "病例库.xlsx", exact: false)
  end

  test "teacher sees docs persisted with pending embedding status", %{
    conn: conn,
    teacher: teacher
  } do
    path = temp_file("cases.xlsx", fixture_xlsx())

    conn
    |> visit("/teacher/ai/knowledge")
    |> upload("文件", path, exact: false)
    |> click_button("上传并入库")
    |> assert_has("span", "处理中", exact: false)

    docs =
      TenantDoc
      |> Ash.Query.filter(source_name == "cases.xlsx")
      |> Ash.read!(actor: teacher, tenant: @tenant)

    assert docs != []
    assert Enum.all?(docs, &(&1.embedding_status == :pending))
  end

  test "teacher deletes a source", %{conn: conn} do
    path = temp_file("del.xlsx", fixture_xlsx())

    conn
    |> visit("/teacher/ai/knowledge")
    |> upload("文件", path, exact: false)
    |> click_button("上传并入库")
    |> assert_has("p", "del.xlsx", exact: false)
    |> click_button("删除")
    |> assert_has("p", "已删除资料", exact: false)
    |> refute_has("p", "del.xlsx", exact: true)
  end

  test "list auto-refreshes when the embedding worker broadcasts", %{conn: conn, teacher: teacher} do
    path = temp_file("auto.xlsx", fixture_xlsx())

    session =
      conn
      |> visit("/teacher/ai/knowledge")
      |> upload("文件", path, exact: false)
      |> click_button("上传并入库")
      |> assert_has("span", "处理中", exact: false)

    doc =
      TenantDoc
      |> Ash.Query.filter(source_name == "auto.xlsx")
      |> Ash.read_one!(actor: teacher, tenant: @tenant)

    {:ok, embedded} =
      TenantDoc.mark_embedding_status(doc, %{embedding_status: :embedded},
        actor: teacher,
        tenant: @tenant
      )

    Phoenix.PubSub.broadcast(
      TcmEdu.PubSub,
      TenantDocEmbeddingWorker.topic(@tenant),
      {:knowledge_docs_event, :doc_embedded,
       %{doc_id: embedded.id, source_name: embedded.source_name, embedding_status: :embedded}}
    )

    session
    |> assert_has("span", "已向量化", exact: false)
  end

  test "toggling the chat switch persists on the source", %{conn: conn, teacher: teacher} do
    path = temp_file("chat.xlsx", fixture_xlsx())

    _session =
      conn
      |> visit("/teacher/ai/knowledge")
      |> upload("文件", path, exact: false)
      |> click_button("上传并入库")
      |> assert_has("button", "问答：开")
      |> click_button("#toggle-in-chat-chat\\.xlsx", "问答：开")
      |> assert_has("button", "问答：关")

    docs =
      TenantDoc
      |> Ash.Query.filter(source_name == "chat.xlsx")
      |> Ash.read!(actor: teacher, tenant: @tenant)

    assert Enum.all?(docs, &(&1.in_chat == false))
  end

  test "editing the source title updates all chunks", %{conn: conn, teacher: teacher} do
    path = temp_file("edit.xlsx", fixture_xlsx())

    conn
    |> visit("/teacher/ai/knowledge")
    |> upload("文件", path, exact: false)
    |> click_button("上传并入库")
    |> assert_has("p", "edit.xlsx", exact: false)
    |> click_button("#edit-edit\\.xlsx", "编辑")
    |> fill_in("编辑标题", with: "桂枝汤病例库新标题")
    |> click_button("保存")
    |> assert_has("p", "桂枝汤病例库新标题")

    docs =
      TenantDoc
      |> Ash.Query.filter(source_name == "edit.xlsx")
      |> Ash.read!(actor: teacher, tenant: @tenant)

    assert Enum.all?(docs, &(&1.title == "桂枝汤病例库新标题"))
  end

  defp fixture_xlsx do
    sheet = %Sheet{
      name: "病例库",
      rows: [
        ["编号", "主诉", "辨证"],
        [1, "恶风发热汗出脉浮缓", "太阳中风证，治以桂枝汤"],
        [2, "项背强几几", "桂枝加葛根汤"]
      ]
    }

    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "病例库.xlsx")
    binary
  end

  defp temp_file(name, binary) do
    dir = Path.join(System.tmp_dir!(), "kb-live-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, binary)
    on_exit(fn -> File.rm_rf!(dir) end)
    path
  end
end
