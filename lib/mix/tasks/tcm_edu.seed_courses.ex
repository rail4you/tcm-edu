defmodule Mix.Tasks.TcmEdu.SeedCourses do
  @moduledoc """
  为指定租户播种演示课程数据（默认 `tenant_default`）。

  用法：

      mix tcm_edu.seed_courses TENANT=default

  内容：5 个分类 × 4 门课程 × 3 章节 × 5 课时 = 20 课程 / 300 课时。
  幂等：目标租户已有课程时跳过。
  """

  use Mix.Task

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.{Chapter, Course, CourseCategory, Lesson}

  @shortdoc "播种演示课程数据到指定租户"

  @categories [
    %{name: "中医基础", slug: "tcm-basics", icon: "book", sort_order: 1},
    %{name: "中药学", slug: "materia-medica", icon: "experiment", sort_order: 2},
    %{name: "方剂学", slug: "formulas", icon: "profile", sort_order: 3},
    %{name: "针灸推拿", slug: "acupuncture-tuina", icon: "thunderbolt", sort_order: 4},
    %{name: "中医临床", slug: "clinical", icon: "heart", sort_order: 5}
  ]

  @courses %{
    "tcm-basics" => [
      %{title: "中医基础理论精讲", subtitle: "阴阳五行入门", level: :beginner},
      %{title: "中医诊断学", subtitle: "望闻问切四诊合参", level: :beginner},
      %{title: "经络腧穴总论", subtitle: "十二经脉与常用腧穴", level: :intermediate},
      %{title: "中医体质学", subtitle: "九种体质辨识与调理", level: :beginner}
    ],
    "materia-medica" => [
      %{title: "中药学入门", subtitle: "四气五味升降浮沉", level: :beginner},
      %{title: "解表药与清热药", subtitle: "辛凉解表苦寒清热", level: :intermediate},
      %{title: "补虚药精讲", subtitle: "气血阴阳之补法", level: :intermediate},
      %{title: "有毒中药安全应用", subtitle: "附子半夏合理使用", level: :advanced}
    ],
    "formulas" => [
      %{title: "方剂学基础", subtitle: "君臣佐使组方原则", level: :beginner},
      %{title: "经方十讲桂枝汤类方", subtitle: "仲景群方之魁", level: :intermediate},
      %{title: "温病名方精析", subtitle: "银翘散桑菊饮白虎汤", level: :advanced},
      %{title: "儿科常用方剂", subtitle: "小儿配伍内服方", level: :intermediate}
    ],
    "acupuncture-tuina" => [
      %{title: "针灸学入门", subtitle: "毫针刺法与得气", level: :beginner},
      %{title: "头颈肩痛针灸治疗", subtitle: "颈椎病落枕偏头痛", level: :intermediate},
      %{title: "小儿推拿手法学", subtitle: "推拿八法与常用穴位", level: :beginner},
      %{title: "艾灸与拔罐实务", subtitle: "温通经络的外治法", level: :intermediate}
    ],
    "clinical" => [
      %{title: "中医内科肺系病证", subtitle: "感冒咳嗽哮病辨治", level: :intermediate},
      %{title: "中医妇科学入门", subtitle: "月经病辨证思路", level: :intermediate},
      %{title: "中医治未病与养生", subtitle: "四季养生与食疗", level: :beginner},
      %{title: "名老中医医案研读", subtitle: "跟师临证思维训练", level: :advanced}
    ]
  }

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    slug = parse_tenant(args)
    tenant = "tenant_" <> slug

    unless schema_exists?(tenant) do
      Mix.shell().error("租户 schema #{tenant} 不存在，先跑 mix tcm_edu.migrate")
      exit({:shutdown, 1})
    end

    seeded? =
      case Course
           |> Ash.Query.filter(title == "中医基础理论精讲")
           |> Ash.read_one(tenant: tenant, authorize?: false) do
        {:ok, %Course{}} -> true
        _ -> false
      end

    if seeded? do
      Mix.shell().info("✓ #{tenant} 已有种子课程，跳过")
    else
      seed!(tenant)
    end
  end

  defp seed!(tenant) do
    teacher = ensure_teacher!(tenant)
    Enum.each(@categories, &seed_category!(tenant, teacher, &1))
    Mix.shell().info("✓ 种子完成：5 分类 / 20 课程 / 60 章节 / 300 课时 → #{tenant}")
  end

  defp seed_category!(tenant, teacher, cat_attrs) do
    {:ok, category} =
      CourseCategory
      |> Ash.Changeset.for_action(:create, cat_attrs)
      |> Ash.create(tenant: tenant, authorize?: false)

    cat_attrs.slug
    |> course_list!()
    |> Enum.each(&seed_course!(tenant, teacher, category, &1))
  end

  defp course_list!(slug), do: Map.fetch!(@courses, slug)

  defp seed_course!(tenant, teacher, category, course_attrs) do
    params =
      Map.merge(course_attrs, %{
        description: "#{course_attrs.title}演示数据。",
        teacher_id: teacher.id,
        category_id: category.id,
        price_cents: 0,
        tags: ["演示"]
      })

    {:ok, course} =
      Course
      |> Ash.Changeset.for_action(:create_course, params)
      |> Ash.create(tenant: tenant, authorize?: false)

    Enum.each(1..3, &seed_chapter!(tenant, course, &1))

    course
    |> Ash.Changeset.for_update(:publish, %{})
    |> Ash.update!(tenant: tenant, authorize?: false)
  end

  defp seed_chapter!(tenant, course, ch_no) do
    {:ok, chapter} =
      Chapter
      |> Ash.Changeset.for_action(:create, %{
        title: "第#{ch_no}章",
        sort_order: ch_no,
        course_id: course.id
      })
      |> Ash.create(tenant: tenant, authorize?: false)

    Enum.each(1..5, &seed_lesson!(tenant, course, chapter, ch_no, &1))
  end

  defp seed_lesson!(tenant, course, chapter, ch_no, lesson_no) do
    free = ch_no == 1 and lesson_no == 1
    base = lesson_body!(course, ch_no, lesson_no, free)

    params =
      Map.merge(base, %{
        title: "课时 #{ch_no}.#{lesson_no}",
        sort_order: lesson_no,
        is_free_preview: free,
        chapter_id: chapter.id
      })

    Lesson
    |> Ash.Changeset.for_action(:create, params)
    |> Ash.create!(tenant: tenant, authorize?: false)
  end

  defp lesson_body!(course, ch_no, lesson_no, free) do
    if free do
      %{
        content_type: :article,
        content_text: "免费试看导学。",
        content_url: nil,
        duration_seconds: 300
      }
    else
      %{
        content_type: :video,
        content_text: nil,
        content_url: "https://example.com/#{course.id}/#{ch_no}-#{lesson_no}.mp4",
        duration_seconds: 900 + lesson_no * 60
      }
    end
  end

  defp ensure_teacher!(tenant) do
    case User
         |> Ash.Query.filter(email == "seed-teacher@example.com")
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %User{} = user} ->
        user

      _ ->
        {:ok, user} =
          User
          |> Ash.Changeset.for_action(:register_with_role, %{
            email: "seed-teacher@example.com",
            name: "演示教师",
            password: "password123",
            role: :teacher
          })
          |> Ash.create(tenant: tenant, authorize?: false)

        user
    end
  end

  defp schema_exists?(name) do
    case TcmEdu.Repo.query("SELECT 1 FROM pg_namespace WHERE nspname = $1", [name]) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end

  defp parse_tenant(args) do
    Enum.find_value(args, "default", fn
      "TENANT=" <> slug -> String.trim(slug)
      _ -> nil
    end)
  end
end
