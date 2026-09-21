defmodule TcmEduWeb.TeacherCourseCoverTest do
  @moduledoc """
  End-to-end coverage for course covers on `/teacher/courses` using
  PhoenixTest: upload a cover in the create modal, replace it in the
  edit modal, then remove it. Files go through AshStorage into the
  in-memory Test service.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course

  @tenant "tenant_default"
  # 1x1 transparent PNG
  @png_base64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  setup %{conn: conn} do
    AshStorage.Service.Test.reset!()

    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "cover-e2e-#{System.unique_integer([:positive])}@example.com",
          name: "Cover E2E",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    cover_path =
      Path.join(System.tmp_dir!(), "cover-e2e-#{System.unique_integer([:positive])}.png")

    File.write!(cover_path, Base.decode64!(@png_base64))
    on_exit(fn -> File.rm(cover_path) end)

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "Cover E2E"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, cover_path: cover_path}
  end

  test "create modal uploads a cover", %{conn: conn, cover_path: cover_path} do
    title = "封面课 #{System.unique_integer([:positive])}"

    conn
    |> visit("/teacher/courses")
    |> click_button("#new-course-btn", "创建课程")
    |> fill_in("课程标题", with: title)
    |> upload("选择封面图片", cover_path)
    |> click_button("#new-course-form", "创建课程")
    |> assert_has("p", "封面已上传")
    |> assert_has("td", title)
    |> assert_has("tbody img")
  end

  test "edit modal replaces and removes the cover", %{
    conn: conn,
    teacher: teacher,
    cover_path: cover_path
  } do
    {:ok, course} =
      Course
      |> Ash.Changeset.for_action(:create_course, %{
        title: "改封面 #{System.unique_integer([:positive])}",
        teacher_id: teacher.id
      })
      |> Ash.create(actor: teacher, tenant: @tenant)

    conn
    |> visit("/teacher/courses")
    |> click_button("#edit-course-#{course.id}", "编辑")
    |> upload("选择封面图片", cover_path)
    |> click_button("#edit-course-form", "保存")
    |> assert_has("p", "封面已更新")
    |> assert_has("tbody img")
    |> click_button("#edit-course-#{course.id}", "编辑")
    |> assert_has("#edit-cover-preview")
    |> click_button("移除当前封面")
    |> assert_has("p", "封面已移除")
    |> refute_has("#edit-cover-preview")
  end
end
