defmodule TcmEduWeb.StudentMdtTest do
  @moduledoc "学生端「MDT 会诊」PhoenixTest。"

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Mdt.{Case, Examples, Message, Room}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "mdt-teacher-#{System.unique_integer([:positive])}@example.com",
          name: "MDT Teacher",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    student =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "mdt-student-#{System.unique_integer([:positive])}@example.com",
          name: "MDT Student",
          password: "password123",
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    # 教师从模板创建一个已发布的 MDT 病例
    {:ok, _mdt_case} = Examples.create!("ami_mdt", teacher, tenant: @tenant)

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "student_id" => student.id,
        "student_role" => "student",
        "student_tenant" => @tenant,
        "student_email" => to_string(student.email),
        "student_name" => "MDT Student"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    {:ok, conn: conn, teacher: teacher, student: student}
  end

  test "教师创建的 MDT 病例在学生端可见并可进入会诊室", %{
    conn: conn,
    student: student
  } do
    [mdt_case] =
      Case
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.read!()

    conn
    |> visit("/mdt")
    |> assert_has("h1", text: "多学科会诊（MDT）")
    |> assert_has("p", text: mdt_case.complaint)
    |> click_button("#start-mdt-#{mdt_case.id}", "进入会诊")
    |> assert_has("a", text: "返回会诊列表")
    |> assert_has("p", text: mdt_case.complaint)
    |> assert_has("span", text: "急诊科（MDT Student）")
    |> assert_has("span", text: "心血管内科（AI 专家）")
    |> assert_has("span", text: "影像科（AI 专家）")
  end

  test "学生会诊发言可持久化；缺 key 时 AI 优雅失败", %{
    conn: conn,
    student: student
  } do
    [mdt_case] =
      Case
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.read!()

    conn =
      conn
      |> visit("/mdt")
      |> click_button("#start-mdt-#{mdt_case.id}", "进入会诊")
      |> fill_in("以「急诊科」身份发言", with: "我初步考虑急性心肌梗死，建议先心电图+肌钙蛋白")
      |> click_button("#mdt-send", "发言")

    [room] =
      Room
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.read!()

    messages =
      Message
      |> Ash.Query.for_read(:for_room, %{room_id: room.id}, actor: student, tenant: @tenant)
      |> Ash.read!()

    assert length(messages) == 1
    assert hd(messages).role == "student:急诊科"
    assert hd(messages).content =~ "急性心肌梗死"
  end

  test "结束并汇总结论在缺 key 时优雅失败", %{
    conn: conn,
    student: student,
    teacher: teacher
  } do
    [mdt_case] =
      Case
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.read!()

    # 先有两条发言（直接入库，绕开 AI）
    conn = conn |> visit("/mdt") |> click_button("#start-mdt-#{mdt_case.id}", "进入会诊")

    [room] =
      Room |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant) |> Ash.read!()

    for msg <- ["患者您好，胸痛多久了？", "我建议先做心电图排除心梗"] do
      Message
      |> Ash.Changeset.for_create(
        :create,
        %{room_id: room.id, role: "student:急诊科", content: msg},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()
    end

    conn
    |> visit("/mdt/rooms/#{room.id}")
    |> click_button("#mdt-conclude", "结束并汇总结论")

    # 缺 key 时 AI 无法汇总，房间保持进行中
    [room2] =
      Room
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.Query.filter(id == ^room.id)
      |> Ash.read!()

    assert room2.status == :open
  end
end
