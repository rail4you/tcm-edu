defmodule TcmEdu.Courses.CourseTest do
  @moduledoc """
  Phase 6 测试：课程域（分类 / 课程 / 章节 / 课时）。

  覆盖（对照 docs/tcm-edu-progress.md §6.9）：
    * 角色可见性：草稿仅作者/管理员可见，发布后学生与匿名可见
    * 发布校验：无章节 / 无课时拒绝，有内容通过并写 published_at
    * 聚合 total_lessons / total_duration_seconds
    * 章节/课时的作者归属策略（teacher B 不能改 teacher A 的）
    * 免费试看匿名可读，非免费匿名拒绝、登录可读（Phase 6 规则）
    * 跨租户隔离
    * 分类 slug 租户内唯一；分类写操作仅管理员
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.{Chapter, Course, CourseCategory, Lesson}
  alias TcmEdu.System.Organization
  alias TcmEdu.Repo

  @tenant "tenant_default"

  describe "course creation" do
    setup do
      {:ok, teacher: create_user!("crs-teacher", :teacher), student: create_user!("crs-student", :student)}
    end

    test "teacher can create a draft course", %{teacher: teacher} do
      assert {:ok, %Course{status: :draft} = course} =
               Course
               |> Ash.Changeset.for_action(:create_course, %{
                 title: "Course #{uniq()}",
                 teacher_id: teacher.id
               })
               |> Ash.create(actor: teacher, tenant: @tenant)

      assert course.teacher_id == teacher.id
    end

    test "student cannot create courses", %{student: student, teacher: teacher} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Course
               |> Ash.Changeset.for_action(:create_course, %{
                 title: "Nope #{uniq()}",
                 teacher_id: teacher.id
               })
               |> Ash.create(actor: student, tenant: @tenant)
    end

    test "anonymous cannot create courses", %{teacher: teacher} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Course
               |> Ash.Changeset.for_action(:create_course, %{
                 title: "Nope #{uniq()}",
                 teacher_id: teacher.id
               })
               |> Ash.create(actor: nil, tenant: @tenant)
    end
  end

  describe "publish flow" do
    setup do
      teacher = create_user!("pub-teacher", :teacher)
      {:ok, course} = create_course!(teacher, "Publish #{uniq()}")
      {:ok, teacher: teacher, course: course}
    end

    test "rejects publish without chapters", %{teacher: teacher, course: course} do
      assert {:error, %Ash.Error.Invalid{}} =
               course
               |> Ash.Changeset.for_update(:publish, %{})
               |> Ash.update(actor: teacher, tenant: @tenant)
    end

    test "rejects publish with chapter but no lessons", %{teacher: teacher, course: course} do
      {:ok, _} = create_chapter!(course, "Ch1")

      assert {:error, %Ash.Error.Invalid{}} =
               course
               |> Ash.Changeset.for_update(:publish, %{})
               |> Ash.update(actor: teacher, tenant: @tenant)
    end

    test "publishes with chapters + lessons and stamps published_at", %{
      teacher: teacher,
      course: course
    } do
      {:ok, chapter} = create_chapter!(course, "Ch1")
      {:ok, _} = create_lesson!(chapter, "L1")

      assert {:ok, %Course{status: :published, published_at: %DateTime{}}} =
               course
               |> Ash.Changeset.for_update(:publish, %{})
               |> Ash.update(actor: teacher, tenant: @tenant)
    end

    test "student cannot publish", %{course: course} do
      student = create_user!("pub-student", :student)
      {:ok, chapter} = create_chapter!(course, "Ch1")
      {:ok, _} = create_lesson!(chapter, "L1")

      assert {:error, %Ash.Error.Forbidden{}} =
               course
               |> Ash.Changeset.for_update(:publish, %{})
               |> Ash.update(actor: student, tenant: @tenant)
    end
  end

  describe "visibility" do
    setup do
      teacher = create_user!("vis-teacher", :teacher)
      student = create_user!("vis-student", :student)
      {:ok, draft} = create_course!(teacher, "Draft #{uniq()}")
      {:ok, draft_pub} = create_course!(teacher, "Pub #{uniq()}")
      {:ok, published} = publish_with_content!(draft_pub, teacher)
      {:ok, teacher: teacher, student: student, draft: draft, published: published}
    end

    test "student list_published sees published only", %{student: student, published: published} do
      assert {:ok, courses} =
               Ash.read(Course, action: :list_published, actor: student, tenant: @tenant)

      ids = Enum.map(courses, & &1.id)
      assert published.id in ids
    end

    test "student cannot see drafts in list_published", %{student: student, draft: draft} do
      assert {:ok, courses} =
               Ash.read(Course, action: :list_published, actor: student, tenant: @tenant)

      refute Enum.any?(courses, &(&1.id == draft.id))
    end

    test "anonymous can list_published", %{published: published} do
      assert {:ok, courses} =
               Ash.read(Course, action: :list_published, actor: nil, tenant: @tenant)

      assert Enum.any?(courses, &(&1.id == published.id))
    end

    test "teacher list_by_teacher sees own courses only", %{teacher: teacher} do
      other = create_user!("vis-teacher2", :teacher)
      {:ok, _other_course} = create_course!(other, "Other #{uniq()}")

      assert {:ok, courses} =
               Course
               |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id})
               |> Ash.read(actor: teacher, tenant: @tenant)

      assert Enum.all?(courses, &(&1.teacher_id == teacher.id))
    end

    test "list_by_category returns published in category", %{teacher: teacher} do
      {:ok, cat} = create_category!("vis-cat")
      {:ok, course} = create_course!(teacher, "Cat #{uniq()}", category_id: cat.id)
      {:ok, _} = publish_with_content!(course, teacher)

      assert {:ok, courses} =
               Course
               |> Ash.Query.for_read(:list_by_category, %{category_id: cat.id})
               |> Ash.read(actor: nil, tenant: @tenant)

      assert Enum.any?(courses, &(&1.id == course.id))
    end
  end

  describe "calculations" do
    test "lesson_count and duration_seconds" do
      teacher = create_user!("agg-teacher", :teacher)
      {:ok, course} = create_course!(teacher, "Agg #{uniq()}")
      {:ok, ch1} = create_chapter!(course, "Ch1")
      {:ok, ch2} = create_chapter!(course, "Ch2")
      {:ok, _} = create_lesson!(ch1, "L1", duration_seconds: 100)
      {:ok, _} = create_lesson!(ch1, "L2", duration_seconds: 200)
      {:ok, _} = create_lesson!(ch2, "L3", duration_seconds: 300)

      assert {:ok, course_fresh} = Ash.get(Course, course.id, actor: teacher, tenant: @tenant)

      loaded =
        Ash.load!(course_fresh, [:lesson_count, :duration_seconds],
          actor: teacher,
          tenant: @tenant
        )

      assert loaded.lesson_count == 3
      assert Decimal.eq?(Decimal.new(loaded.duration_seconds), Decimal.new(600))
    end
  end

  describe "chapter/lesson ownership" do
    setup do
      teacher_a = create_user!("own-a", :teacher)
      teacher_b = create_user!("own-b", :teacher)
      admin = create_user!("own-admin", :tenant_admin)
      {:ok, course} = create_course!(teacher_a, "Own #{uniq()}")
      {:ok, chapter} = create_chapter!(course, "Ch1")
      {:ok, lesson} = create_lesson!(chapter, "L1")
      {:ok, teacher_a: teacher_a, teacher_b: teacher_b, admin: admin, chapter: chapter, lesson: lesson}
    end

    test "teacher B cannot update teacher A's chapter", %{teacher_b: teacher_b, chapter: chapter} do
      assert {:error, %Ash.Error.Forbidden{}} =
               chapter
               |> Ash.Changeset.for_update(:update, %{title: "Hijacked"})
               |> Ash.update(actor: teacher_b, tenant: @tenant)
    end

    test "teacher B cannot update teacher A's lesson", %{teacher_b: teacher_b, lesson: lesson} do
      assert {:error, %Ash.Error.Forbidden{}} =
               lesson
               |> Ash.Changeset.for_update(:update, %{title: "Hijacked"})
               |> Ash.update(actor: teacher_b, tenant: @tenant)
    end

    test "admin can update any chapter", %{admin: admin, chapter: chapter} do
      assert {:ok, %{title: "Admin Edit"}} =
               chapter
               |> Ash.Changeset.for_update(:update, %{title: "Admin Edit"})
               |> Ash.update(actor: admin, tenant: @tenant)
    end

    test "student cannot create chapters", %{chapter: chapter} do
      student = create_user!("own-student", :student)

      assert {:error, %Ash.Error.Forbidden{}} =
               Chapter
               |> Ash.Changeset.for_action(:create, %{title: "X", course_id: chapter.course_id})
               |> Ash.create(actor: student, tenant: @tenant)
    end
  end

  describe "lesson preview visibility (Phase 6 rule)" do
    setup do
      teacher = create_user!("prev-teacher", :teacher)
      student = create_user!("prev-student", :student)
      {:ok, course} = create_course!(teacher, "Prev #{uniq()}")
      {:ok, chapter} = create_chapter!(course, "Ch1")
      {:ok, free} = create_lesson!(chapter, "Free", is_free_preview: true)
      {:ok, paid} = create_lesson!(chapter, "Paid")
      {:ok, student: student, free: free, paid: paid}
    end

    test "anonymous can read free preview lessons", %{free: free} do
      assert {:ok, lessons} = Ash.read(Lesson, actor: nil, tenant: @tenant)
      assert Enum.any?(lessons, &(&1.id == free.id))
    end

    test "anonymous cannot read non-free lessons", %{paid: paid} do
      assert {:ok, lessons} = Ash.read(Lesson, actor: nil, tenant: @tenant)
      # 公开读返回的应全是免费课时
      assert Enum.all?(lessons, & &1.is_free_preview)
      refute Enum.any?(lessons, &(&1.id == paid.id))
    end

    test "logged-in student can read non-free (tightened in Phase 7)", %{
      student: student,
      paid: paid
    } do
      assert {:ok, fetched} = Ash.get(Lesson, paid.id, actor: student, tenant: @tenant)
      assert fetched.id == paid.id
    end
  end

  describe "categories" do
    test "duplicate slug rejected within tenant" do
      {:ok, existing} = create_category!("dup-cat")

      assert {:error, %Ash.Error.Invalid{}} =
               CourseCategory
               |> Ash.Changeset.for_action(:create, %{name: "Dup", slug: existing.slug})
               |> Ash.create(tenant: @tenant, authorize?: false)
    end

    test "teacher cannot create categories" do
      teacher = create_user!("cat-teacher", :teacher)

      assert {:error, %Ash.Error.Forbidden{}} =
               CourseCategory
               |> Ash.Changeset.for_action(:create, %{name: "X", slug: "x-#{uniq()}"})
               |> Ash.create(actor: teacher, tenant: @tenant)
    end

    test "anonymous can list categories" do
      {:ok, _} = create_category!("pub-cat")
      assert {:ok, cats} = Ash.read(CourseCategory, actor: nil, tenant: @tenant)
      assert length(cats) >= 1
    end
  end

  describe "cross-tenant isolation" do
    test "courses in tenant B invisible in tenant A" do
      org_b = create_org!("phase6-iso")
      teacher_b = create_user_in!(org_b.schema_name, "iso-teacher", :teacher)
      {:ok, draft_b} = create_course_in!(teacher_b, org_b.schema_name, "Iso #{uniq()}")
      {:ok, course_b} = publish_in!(draft_b, teacher_b, org_b.schema_name)

      # A 租户查不到 B 的课
      assert {:ok, courses_a} =
               Ash.read(Course, action: :list_published, actor: nil, tenant: @tenant)

      refute Enum.any?(courses_a, &(&1.id == course_b.id))

      # B 租户能查到（已发布，匿名可见）
      assert {:ok, fetched} = Ash.get(Course, course_b.id, actor: nil, tenant: org_b.schema_name)
      assert fetched.id == course_b.id
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

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

  defp create_category!(slug_root) do
    slug = "#{slug_root}-#{uniq()}"

    CourseCategory
    |> Ash.Changeset.for_action(:create, %{name: slug, slug: slug})
    |> Ash.create(tenant: @tenant, authorize?: false)
  end

  defp create_course!(teacher, title, extra \\ []) do
    attrs =
      Map.merge(%{title: title, teacher_id: teacher.id}, Map.new(extra))

    Course
    |> Ash.Changeset.for_action(:create_course, attrs)
    |> Ash.create(actor: teacher, tenant: @tenant)
  end

  defp create_course_in!(teacher, tenant, title) do
    Course
    |> Ash.Changeset.for_action(:create_course, %{title: title, teacher_id: teacher.id})
    |> Ash.create(actor: teacher, tenant: tenant)
  end

  defp create_chapter!(course, title) do
    Chapter
    |> Ash.Changeset.for_action(:create, %{title: title, course_id: course.id})
    |> Ash.create(tenant: @tenant, authorize?: false)
  end

  defp create_lesson!(chapter, title, opts \\ []) do
    attrs =
      Map.merge(
        %{title: title, chapter_id: chapter.id, content_type: :video, duration_seconds: 60},
        Map.new(opts)
      )

    Lesson
    |> Ash.Changeset.for_action(:create, attrs)
    |> Ash.create(tenant: @tenant, authorize?: false)
  end

  defp publish!(course, teacher) do
    publish_in!(course, teacher, @tenant)
  end

  defp publish_in!(course, teacher, tenant) do
    {:ok, chapter} =
      Chapter
      |> Ash.Changeset.for_action(:create, %{title: "Ch1", course_id: course.id})
      |> Ash.create(tenant: tenant, authorize?: false)

    {:ok, _} =
      Lesson
      |> Ash.Changeset.for_action(:create, %{title: "L1", chapter_id: chapter.id})
      |> Ash.create(tenant: tenant, authorize?: false)

    course
    |> Ash.Changeset.for_update(:publish, %{})
    |> Ash.update(actor: teacher, tenant: tenant)
  end

  defp publish_with_content!(course, teacher) do
    {:ok, chapter} = create_chapter!(course, "Ch1")
    {:ok, _} = create_lesson!(chapter, "L1")
    publish!(course, teacher)
  end

  defp create_org!(slug_root) do
    slug = "#{slug_root}-#{uniq()}"
    org = Ash.create!(Organization, %{name: slug, slug: slug}, authorize?: false)
    register_org_cleanup(org)
    org
  end

  defp register_org_cleanup(%Organization{} = org) do
    on_exit(fn ->
      try do
        if schema_exists?(org.schema_name) do
          Repo.query("DROP SCHEMA IF EXISTS \"#{org.schema_name}\" CASCADE")
        end
      rescue
        _ -> :ok
      end
    end)
  end

  defp schema_exists?(name) do
    case Repo.query("SELECT 1 FROM pg_namespace WHERE nspname = $1", [name]) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end
end
