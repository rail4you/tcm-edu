defmodule TcmEdu.Enrollment.EnrollmentTest do
  @moduledoc """
  Phase 7 测试：选课与进度（Enrollment / Progress）。

  覆盖（对照 docs/tcm-edu-progress.md §7.5）：
    * 学生选课 → 创建 enrollment；重复选课拒绝（422 Invalid）
    * 草稿课程拒绝选课；教师/匿名选课被 Forbidden
    * my_enrollments 只看自己的；跨用户不可见
    * cancel / mark_completed：本人或管理员；他人 Forbidden
    * progress 心跳 upsert：创建→更新同一条；100% 自动完结
    * 跨用户不能改他人进度；教师可读自己课程的进度
    * 跨租户隔离
    * student_count 聚合 + list_popular 排序
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.{Chapter, Course, Lesson}
  alias TcmEdu.Enrollment.{Enrollment, Progress}

  @tenant "tenant_default"

  # ─── 选课 ───

  describe "enroll" do
    setup do
      teacher = create_user!("enr-teacher", :teacher)
      student = create_user!("enr-student", :student)
      {:ok, course} = create_published_course!(teacher, "Enroll #{uniq()}")
      {:ok, teacher: teacher, student: student, course: course}
    end

    test "student can enroll in a published course", %{student: student, course: course} do
      assert {:ok, %Enrollment{status: :active} = enrollment} =
               Enrollment
               |> Ash.Changeset.for_action(:enroll, %{course_id: course.id},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()

      assert enrollment.user_id == student.id
      assert enrollment.course_id == course.id
    end

    test "duplicate enrollment is rejected", %{student: student, course: course} do
      {:ok, _} = enroll!(student, course)

      assert {:error, %Ash.Error.Invalid{}} =
               Enrollment
               |> Ash.Changeset.for_action(:enroll, %{course_id: course.id},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end

    test "cannot enroll in a draft course", %{teacher: teacher, student: student} do
      {:ok, draft} = create_draft_course!(teacher, "Draft #{uniq()}")

      assert {:error, %Ash.Error.Invalid{}} =
               Enrollment
               |> Ash.Changeset.for_action(:enroll, %{course_id: draft.id},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end

    test "teacher cannot enroll", %{teacher: teacher, course: course} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Enrollment
               |> Ash.Changeset.for_action(:enroll, %{course_id: course.id},
                 actor: teacher,
                 tenant: @tenant
               )
               |> Ash.create()
    end

    test "anonymous cannot enroll", %{course: course} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Enrollment
               |> Ash.Changeset.for_action(:enroll, %{course_id: course.id},
                 actor: nil,
                 tenant: @tenant
               )
               |> Ash.create()
    end
  end

  # ─── 我的选课 ───

  describe "my_enrollments" do
    setup do
      teacher = create_user!("mye-teacher", :teacher)
      student_a = create_user!("mye-student-a", :student)
      student_b = create_user!("mye-student-b", :student)
      {:ok, course} = create_published_course!(teacher, "MyEnr #{uniq()}")
      {:ok, teacher: teacher, student_a: student_a, student_b: student_b, course: course}
    end

    test "student sees only their own enrollments", %{
      student_a: student_a,
      student_b: student_b,
      course: course
    } do
      {:ok, _} = enroll!(student_a, course)
      {:ok, _} = enroll!(student_b, course)

      assert {:ok, enrollments} =
               Enrollment
               |> Ash.Query.for_read(:my_enrollments, %{}, actor: student_a)
               |> Ash.read(tenant: @tenant)

      assert Enum.map(enrollments, & &1.user_id) == [student_a.id]
    end

    test "admin sees all enrollments", %{
      teacher: teacher,
      student_a: student_a,
      student_b: student_b,
      course: course
    } do
      {:ok, _} = enroll!(student_a, course)
      {:ok, _} = enroll!(student_b, course)
      admin = create_user!("mye-admin", :tenant_admin)

      assert {:ok, enrollments} =
               Enrollment
               |> Ash.Query.for_read(:read, %{}, actor: admin)
               |> Ash.read(tenant: @tenant)

      assert length(enrollments) == 2
      _ = teacher
    end

    test "teacher sees enrollments of their own courses", %{
      teacher: teacher,
      student_a: student_a,
      course: course
    } do
      {:ok, _} = enroll!(student_a, course)

      assert {:ok, enrollments} =
               Enrollment
               |> Ash.Query.for_read(:read, %{}, actor: teacher)
               |> Ash.read(tenant: @tenant)

      assert Enum.map(enrollments, & &1.user_id) == [student_a.id]
    end

    test "teacher cannot see other teachers' enrollments", %{course: _course} do
      other_teacher = create_user!("mye-teacher-b", :teacher)
      other_student = create_user!("mye-student-c", :student)
      {:ok, other_course} = create_published_course!(other_teacher, "Other #{uniq()}")
      {:ok, _} = enroll!(other_student, other_course)

      me = create_user!("mye-teacher-me", :teacher)

      assert {:ok, []} =
               Enrollment
               |> Ash.Query.for_read(:read, %{}, actor: me)
               |> Ash.read(tenant: @tenant)
    end
  end

  # ─── 取消 / 学完 ───

  describe "cancel and complete" do
    setup do
      teacher = create_user!("cc-teacher", :teacher)
      student = create_user!("cc-student", :student)
      other = create_user!("cc-other", :student)
      admin = create_user!("cc-admin", :tenant_admin)
      {:ok, course} = create_published_course!(teacher, "CC #{uniq()}")
      {:ok, enrollment} = enroll!(student, course)

      {:ok,
       teacher: teacher, student: student, other: other, admin: admin, enrollment: enrollment}
    end

    test "student can cancel their own enrollment", %{student: student, enrollment: enrollment} do
      assert {:ok, %Enrollment{status: :cancelled}} =
               enrollment
               |> Ash.Changeset.for_update(:cancel, %{})
               |> Ash.update(actor: student, tenant: @tenant)
    end

    test "other student cannot cancel", %{other: other, enrollment: enrollment} do
      assert {:error, %Ash.Error.Forbidden{}} =
               enrollment
               |> Ash.Changeset.for_update(:cancel, %{})
               |> Ash.update(actor: other, tenant: @tenant)
    end

    test "admin can cancel", %{admin: admin, enrollment: enrollment} do
      assert {:ok, %Enrollment{status: :cancelled}} =
               enrollment
               |> Ash.Changeset.for_update(:cancel, %{})
               |> Ash.update(actor: admin, tenant: @tenant)
    end

    test "mark_completed sets status and completed_at", %{
      student: student,
      enrollment: enrollment
    } do
      assert {:ok, %Enrollment{status: :completed} = done} =
               enrollment
               |> Ash.Changeset.for_update(:mark_completed, %{})
               |> Ash.update(actor: student, tenant: @tenant)

      assert %DateTime{} = done.completed_at
    end
  end

  # ─── 进度心跳 ───

  describe "progress heartbeat" do
    setup do
      teacher = create_user!("pg-teacher", :teacher)
      student = create_user!("pg-student", :student)
      {:ok, course} = create_published_course!(teacher, "PG #{uniq()}")
      {:ok, chapter} = create_chapter!(course, "Ch1")
      {:ok, lesson} = create_lesson!(chapter, "L1")
      {:ok, enrollment} = enroll!(student, course)

      {:ok,
       teacher: teacher, student: student, enrollment: enrollment, lesson: lesson, course: course}
    end

    test "upsert creates then updates the same record", %{
      student: student,
      enrollment: enrollment,
      lesson: lesson
    } do
      assert {:ok, %Progress{progress_pct: 30} = p1} =
               Progress
               |> Ash.Changeset.for_action(:upsert_progress, %{
                 enrollment_id: enrollment.id,
                 lesson_id: lesson.id,
                 progress_pct: 30,
                 last_position_seconds: 100
               })
               |> Ash.create(actor: student, tenant: @tenant)

      assert {:ok, %Progress{progress_pct: 60} = p2} =
               Progress
               |> Ash.Changeset.for_action(:upsert_progress, %{
                 enrollment_id: enrollment.id,
                 lesson_id: lesson.id,
                 progress_pct: 60,
                 last_position_seconds: 200
               })
               |> Ash.create(actor: student, tenant: @tenant)

      assert p1.id == p2.id
    end

    test "reaching 100 auto-completes", %{
      student: student,
      enrollment: enrollment,
      lesson: lesson
    } do
      assert {:ok, %Progress{status: :completed} = done} =
               Progress
               |> Ash.Changeset.for_action(:upsert_progress, %{
                 enrollment_id: enrollment.id,
                 lesson_id: lesson.id,
                 progress_pct: 100
               })
               |> Ash.create(actor: student, tenant: @tenant)

      assert %DateTime{} = done.completed_at
    end

    test "other student cannot report progress", %{enrollment: enrollment, lesson: lesson} do
      other = create_user!("pg-other", :student)

      assert {:error, %Ash.Error.Forbidden{}} =
               Progress
               |> Ash.Changeset.for_action(:upsert_progress, %{
                 enrollment_id: enrollment.id,
                 lesson_id: lesson.id,
                 progress_pct: 10
               })
               |> Ash.create(actor: other, tenant: @tenant)
    end

    test "other student cannot update progress", %{
      student: student,
      enrollment: enrollment,
      lesson: lesson
    } do
      {:ok, progress} =
        Progress
        |> Ash.Changeset.for_action(:upsert_progress, %{
          enrollment_id: enrollment.id,
          lesson_id: lesson.id,
          progress_pct: 10
        })
        |> Ash.create(actor: student, tenant: @tenant)

      other = create_user!("pg-other2", :student)

      assert {:error, %Ash.Error.Forbidden{}} =
               progress
               |> Ash.Changeset.for_update(:update, %{progress_pct: 50})
               |> Ash.update(actor: other, tenant: @tenant)
    end

    test "teacher can read progress of their own course", %{
      teacher: teacher,
      student: student,
      enrollment: enrollment,
      lesson: lesson
    } do
      {:ok, _} =
        Progress
        |> Ash.Changeset.for_action(:upsert_progress, %{
          enrollment_id: enrollment.id,
          lesson_id: lesson.id,
          progress_pct: 10
        })
        |> Ash.create(actor: student, tenant: @tenant)

      assert {:ok, [_]} =
               Progress
               |> Ash.Query.for_read(:read, %{}, actor: teacher)
               |> Ash.read(tenant: @tenant)
    end

    test "progress_pct over 100 is rejected", %{
      student: student,
      enrollment: enrollment,
      lesson: lesson
    } do
      assert {:error, %Ash.Error.Invalid{}} =
               Progress
               |> Ash.Changeset.for_action(:upsert_progress, %{
                 enrollment_id: enrollment.id,
                 lesson_id: lesson.id,
                 progress_pct: 101
               })
               |> Ash.create(actor: student, tenant: @tenant)
    end
  end

  # ─── 跨租户隔离 ───

  describe "tenant isolation" do
    test "enrollments are invisible across tenants" do
      teacher = create_user!("iso-teacher", :teacher)
      student = create_user!("iso-student", :student)
      {:ok, course} = create_published_course!(teacher, "Iso #{uniq()}")
      {:ok, _} = enroll!(student, course)

      {:ok, other_org} =
        TcmEdu.System.Organization
        |> Ash.Changeset.for_action(:create_with_schema, %{
          name: "Iso Org #{uniq()}",
          slug: "iso-#{uniq()}",
          contact_email: "iso-#{uniq()}@example.com"
        })
        |> Ash.create(authorize?: false)

      other_tenant = other_org.schema_name
      other_teacher = create_user_in!(other_tenant, "iso-teacher-b", :teacher)
      other_student = create_user_in!(other_tenant, "iso-student-b", :student)

      assert {:ok, []} =
               Enrollment
               |> Ash.Query.for_read(:read, %{}, actor: other_student)
               |> Ash.read(tenant: other_tenant)

      # 新租户教师在自己租户也看不到别的租户的选课
      assert {:ok, []} =
               Enrollment
               |> Ash.Query.for_read(:read, %{}, actor: other_teacher)
               |> Ash.read(tenant: other_tenant)
    end
  end

  # ─── student_count + list_popular ───

  describe "student_count and list_popular" do
    setup do
      teacher = create_user!("pop-teacher", :teacher)
      {:ok, hot} = create_published_course!(teacher, "Hot #{uniq()}")
      {:ok, cold} = create_published_course!(teacher, "Cold #{uniq()}")
      {:ok, teacher: teacher, hot: hot, cold: cold}
    end

    test "student_count reflects active enrollments", %{hot: hot} do
      s1 = create_user!("pop-s1", :student)
      s2 = create_user!("pop-s2", :student)
      s3 = create_user!("pop-s3", :student)
      {:ok, _} = enroll!(s1, hot)
      {:ok, e2} = enroll!(s2, hot)
      {:ok, _} = enroll!(s3, hot)

      # 取消一单后只剩 2 个 active
      {:ok, _} =
        e2 |> Ash.Changeset.for_update(:cancel, %{}) |> Ash.update(actor: s2, tenant: @tenant)

      assert {:ok, loaded} =
               Course
               |> Ash.Query.filter(id == ^hot.id)
               |> Ash.Query.load(:student_count)
               |> Ash.read_one(actor: nil, tenant: @tenant)

      assert loaded.student_count == 2
    end

    test "list_popular orders by student_count desc, published only", %{
      teacher: teacher,
      hot: hot,
      cold: cold
    } do
      for i <- 1..3 do
        s = create_user!("pop-hot-#{i}", :student)
        {:ok, _} = enroll!(s, hot)
      end

      s = create_user!("pop-cold-1", :student)
      {:ok, _} = enroll!(s, cold)

      # 草稿课程即使有人也排不上（选不上草稿；直接验证过滤）
      {:ok, _draft} = create_draft_course!(teacher, "DraftPop #{uniq()}")

      assert {:ok, courses} =
               Course
               |> Ash.Query.for_read(:list_popular, %{}, actor: nil)
               |> Ash.read(tenant: @tenant)

      ids = Enum.map(courses, & &1.id)
      assert ids == [hot.id, cold.id]
      assert length(courses) <= 10
      assert Enum.all?(courses, &(&1.status == :published))
    end
  end

  # ─── 教师/管理员代学生选课 ───

  describe "enroll_student (teacher manages roster)" do
    setup do
      teacher = create_user!("es-teacher", :teacher)
      student = create_user!("es-student", :student)
      admin = create_user!("es-admin", :tenant_admin)
      {:ok, course} = create_published_course!(teacher, "ES #{uniq()}")
      {:ok, teacher: teacher, student: student, admin: admin, course: course}
    end

    test "course owner can enroll a student", %{
      teacher: teacher,
      student: student,
      course: course
    } do
      assert {:ok, %Enrollment{status: :active} = enrollment} =
               enroll_student(teacher, course, student)

      assert enrollment.user_id == student.id
      assert enrollment.course_id == course.id
    end

    test "admin can enroll a student", %{admin: admin, student: student, course: course} do
      assert {:ok, %Enrollment{status: :active}} = enroll_student(admin, course, student)
    end

    test "another teacher cannot enroll into a course they do not own", %{
      student: student,
      course: course
    } do
      other = create_user!("es-other", :teacher)

      assert {:error, %Ash.Error.Invalid{}} = enroll_student(other, course, student)
    end

    test "cannot enroll a non-student user", %{teacher: teacher, admin: admin, course: course} do
      assert {:error, %Ash.Error.Invalid{}} = enroll_student(teacher, course, admin)
    end

    test "re-adding a cancelled student reactivates the same enrollment", %{
      teacher: teacher,
      student: student,
      course: course
    } do
      {:ok, enrollment} = enroll_student(teacher, course, student)

      {:ok, cancelled} =
        enrollment
        |> Ash.Changeset.for_update(:cancel, %{})
        |> Ash.update(actor: student, tenant: @tenant)

      assert cancelled.status == :cancelled

      assert {:ok, reactivated} = enroll_student(teacher, course, student)
      assert reactivated.id == enrollment.id
      assert reactivated.status == :active
    end

    test "course teacher can remove a student via cancel", %{
      teacher: teacher,
      student: student,
      course: course
    } do
      {:ok, enrollment} = enroll_student(teacher, course, student)

      assert {:ok, %Enrollment{status: :cancelled}} =
               enrollment
               |> Ash.Changeset.for_update(:cancel, %{})
               |> Ash.update(actor: teacher, tenant: @tenant)
    end

    test "removing reactivates availability and drops student_count", %{
      teacher: teacher,
      student: student,
      course: course
    } do
      {:ok, enrollment} = enroll_student(teacher, course, student)

      assert {:ok, loaded} =
               Course
               |> Ash.Query.filter(id == ^course.id)
               |> Ash.Query.load(:student_count)
               |> Ash.read_one(actor: nil, tenant: @tenant)

      assert loaded.student_count == 1

      {:ok, _} =
        enrollment
        |> Ash.Changeset.for_update(:cancel, %{})
        |> Ash.update(actor: teacher, tenant: @tenant)

      assert {:ok, loaded} =
               Course
               |> Ash.Query.filter(id == ^course.id)
               |> Ash.Query.load(:student_count)
               |> Ash.read_one(actor: nil, tenant: @tenant)

      assert loaded.student_count == 0
    end
  end

  # ─── helpers ───

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(prefix, role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "#{prefix}-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_user_in!(tenant, prefix, role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "#{prefix}-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: tenant, authorize?: false)

    user
  end

  defp create_draft_course!(teacher, title) do
    Course
    |> Ash.Changeset.for_action(:create_course, %{title: title, teacher_id: teacher.id})
    |> Ash.create(actor: teacher, tenant: @tenant)
  end

  defp create_published_course!(teacher, title) do
    {:ok, course} = create_draft_course!(teacher, title)
    {:ok, chapter} = create_chapter!(course, "Ch1")
    {:ok, _} = create_lesson!(chapter, "L1")

    course
    |> Ash.Changeset.for_update(:publish, %{})
    |> Ash.update(actor: teacher, tenant: @tenant)
  end

  defp create_chapter!(course, title) do
    Chapter
    |> Ash.Changeset.for_action(:create, %{title: title, course_id: course.id})
    |> Ash.create(tenant: @tenant, authorize?: false)
  end

  defp create_lesson!(chapter, title) do
    Lesson
    |> Ash.Changeset.for_action(:create, %{title: title, chapter_id: chapter.id})
    |> Ash.create(tenant: @tenant, authorize?: false)
  end

  defp enroll!(student, course) do
    # 注意：actor + tenant 必须在 for_action 时传入（与 RPC 保持一致）。
    # 若只在 Ash.create 传 opts，create 的 validate 跑在 tenant 进来之前，
    # 且 set_attribute(actor(:id)) 会取到 nil。
    Enrollment
    |> Ash.Changeset.for_action(:enroll, %{course_id: course.id}, actor: student, tenant: @tenant)
    |> Ash.create()
  end

  defp enroll_student(actor, course, student) do
    Enrollment
    |> Ash.Changeset.for_action(
      :enroll_student,
      %{course_id: course.id, user_id: student.id},
      actor: actor,
      tenant: @tenant
    )
    |> Ash.create()
  end
end
