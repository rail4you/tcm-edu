defmodule TcmEduWeb.TeacherCourseStudentsLiveTest do
  @moduledoc """
  E2E coverage for teacher course roster management
  (`/teacher/courses/:id/students`):

    * the owning teacher sees the candidate list and can enroll a student,
    * enrolled students move from "add" to the roster,
    * an enrolled student can be removed (cancelled),
    * a teacher cannot manage another teacher's course.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course
  alias TcmEdu.Enrollment.Enrollment

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher = create_user!("tcs-teacher", :teacher, "任课教师")
    student1 = create_user!("tcs-s1", :student, "学生甲")
    student2 = create_user!("tcs-s2", :student, "学生乙")
    {:ok, course} = create_course!(teacher, "选课测试 #{uniq()}")

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "任课教师"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, student1: student1, student2: student2, course: course}
  end

  test "lists candidates and adds a student to the roster", %{
    conn: conn,
    course: course,
    student1: student1
  } do
    conn
    |> visit("/teacher/courses/#{course.id}/students")
    |> assert_has("main", "选课管理")
    |> assert_has("#candidate-#{student1.id}", "学生甲")
    |> click_button("#add-student-#{student1.id}", "添加")
    |> assert_has("tr", "学生甲")
    |> refute_has("#candidate-#{student1.id}")
    |> assert_has("main", "已选 1 人")
  end

  test "removing an enrolled student frees them for re-adding", %{
    conn: conn,
    teacher: teacher,
    course: course,
    student1: student1
  } do
    {:ok, enrollment} = enroll_student!(teacher, course, student1)

    conn
    |> visit("/teacher/courses/#{course.id}/students")
    |> assert_has("#enrollment-#{enrollment.id}", "学生甲")
    |> click_button("#remove-student-#{enrollment.id}", "移除")
    |> assert_has("#candidate-#{student1.id}", "学生甲")
    |> refute_has("#enrollment-#{enrollment.id}")
  end

  test "candidate list hides already enrolled students", %{
    conn: conn,
    teacher: teacher,
    course: course,
    student1: student1,
    student2: student2
  } do
    {:ok, _} = enroll_student!(teacher, course, student1)

    conn
    |> visit("/teacher/courses/#{course.id}/students")
    |> refute_has("#candidate-#{student1.id}")
    |> assert_has("#candidate-#{student2.id}", "学生乙")
  end

  test "another teacher cannot manage the course", %{conn: conn, student1: student1} do
    other_teacher = create_user!("tcs-other", :teacher, "别的老师")
    {:ok, other_course} = create_course!(other_teacher, "别人的课 #{uniq()}")

    # 用任课教师 A 的 session 打开教师 B 的课程选课页 → 被挡回课程列表
    conn
    |> visit("/teacher/courses/#{other_course.id}/students")
    |> assert_has("main", "我的课程")

    _ = student1
  end

  # ─── helpers ───

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(prefix, role, name) do
    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{
        email: "#{prefix}-#{uniq()}@example.com",
        name: name,
        password: "password123",
        role: role
      },
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()
  end

  defp create_course!(teacher, title) do
    Course
    |> Ash.Changeset.for_action(:create_course, %{title: title, teacher_id: teacher.id})
    |> Ash.create(actor: teacher, tenant: @tenant)
  end

  defp enroll_student!(teacher, course, student) do
    Enrollment
    |> Ash.Changeset.for_action(
      :enroll_student,
      %{course_id: course.id, user_id: student.id},
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end
end
