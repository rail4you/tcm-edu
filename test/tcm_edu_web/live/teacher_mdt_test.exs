defmodule TcmEduWeb.TeacherMdtTest do
  @moduledoc "教师端 MDT：手动新建病例 + 会诊记录查看（PhoenixTest）。"

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Mdt.{Case, Room}

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

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "MDT Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher}
  end

  test "手动新建病例并发布", %{conn: conn} do
    conn
    |> visit("/teacher/mdt")
    |> assert_has("p", "病例列表")
    |> click_button("新建病例")
    |> fill_in("病例名称", with: "胸痛待查会诊")
    |> fill_in("患者主诉", with: "间断胸痛 1 月")
    |> fill_in("参与科室", with: "内科，外科，影像科")
    |> click_button("#mdt-case-form button[type='submit']", "创建并发布")
    |> assert_has("p", "病例已创建并发布")
    |> assert_has("table", "胸痛待查会诊")
  end

  test "病例可展开会诊记录并查看对话", %{conn: conn, teacher: teacher} do
    {:ok, case} =
      Case.create_case(
        %{
          name: "手动病例#{System.unique_integer([:positive])}",
          complaint: "胸闷气短",
          departments: ["内科"],
          status: :published,
          created_by_id: teacher.id,
          created_by_email: to_string(teacher.email)
        },
        actor: teacher,
        tenant: @tenant
      )

    {:ok, room} =
      Room.create_room(
        %{
          case_id: case.id,
          owner_id: teacher.id,
          case_snapshot: %{
            "name" => case.name,
            "complaint" => case.complaint,
            "departments" => ["内科"]
          }
        },
        actor: teacher,
        tenant: @tenant
      )

    conn
    |> visit("/teacher/mdt")
    |> assert_has("table", case.name)
    |> click_button("会诊记录")
    |> click_button("button[phx-click='open-room']", "0 条")
    |> assert_has("div[role='dialog']", case.name)
    |> assert_has("div[role='dialog']", "这场会诊还没有发言")

    assert room.case_id == case.id
  end
end
