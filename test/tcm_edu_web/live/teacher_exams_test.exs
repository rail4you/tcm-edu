defmodule TcmEduWeb.TeacherExamsTest do
  @moduledoc """
  教师端考试模块端到端测试（PhoenixTest）：
    * 新建试卷 → 组卷页选题 → 发布 → 跳转分配页
    * 批量分配：学生表格 + checkbox 多选 → 分配
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Exam.{Exam, ExamQuestion}
  alias TcmEdu.Quiz.{Question, QuestionBank}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "exam-e2e-#{System.unique_integer([:positive])}@example.com",
          name: "考试老师",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    bank =
      QuestionBank.create_question_bank!(%{name: "考试题库#{System.unique_integer([:positive])}"},
        actor: teacher,
        tenant: @tenant
      )

    {:ok, q1} = create_question!(teacher, bank, "单选：丹参的功效是", "A")
    {:ok, q2} = create_question!(teacher, bank, "判断：膀胱是贮藏尿液的器官", "对")
    student1 = create_student!("张三")
    student2 = create_student!("李四")

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "考试老师"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok,
     conn: conn,
     teacher: teacher,
     bank: bank,
     q1: q1,
     q2: q2,
     student1: student1,
     student2: student2}
  end

  test "create exam, compose from bank, publish goes to assign page", %{
    conn: conn,
    bank: bank,
    q1: q1
  } do
    conn
    |> visit("/teacher/exams")
    |> click_button("#new-exam-btn", "新建试卷")
    |> fill_in("试卷名称", with: "期中考试#{System.unique_integer([:positive])}")
    |> click_button("创建")
    |> assert_has("p", "试卷组卷")
    |> select("#build-bank-select", "选择题库", option: bank.name, exact_option: false)
    |> click_button("#add-question-#{q1.id}", "加入")
    |> assert_has("p", "1 题")
    |> click_button("#publish-exam-btn", "发布试卷")
    |> assert_has("p", "分配试卷")
    |> assert_has("p", "选择学生")
  end

  test "batch assign students via checkbox table", %{
    conn: conn,
    teacher: teacher,
    bank: bank,
    q1: q1,
    q2: q2,
    student1: student1,
    student2: student2
  } do
    exam = create_published_exam!(teacher, bank, q1, q2)

    conn
    |> visit("/teacher/exams/#{exam.id}/assign")
    |> assert_has("p", "选择学生")
    |> check("选择 #{student1.name}")
    |> check("选择 #{student2.name}")
    |> click_button("#assign-selected-btn", "分配选中学生")
    |> assert_has("p", "已分配 2 名学生")
    |> assert_has("span", "已分配", count: 2)
  end

  # ── helpers ───────────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_student!(name) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "exam-student-#{uniq()}@example.com",
        name: name,
        password: "password123",
        role: :student
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_question!(teacher, bank, stem, answer) do
    attrs = %{bank_id: bank.id, stem: "#{stem}？#{uniq()}"}

    attrs =
      if answer in ["对", "错"] do
        Map.merge(attrs, %{type: :judge, options: [], answer: answer})
      else
        Map.merge(attrs, %{
          type: :single,
          options: [
            %{label: "A", text: "活血祛瘀", correct: true},
            %{label: "B", text: "补气"}
          ],
          answer: "A"
        })
      end

    Question
    |> Ash.Changeset.for_action(:create, attrs, actor: teacher, tenant: @tenant)
    |> Ash.create()
  end

  defp create_published_exam!(teacher, _bank, q1, q2) do
    {:ok, exam} =
      Exam
      |> Ash.Changeset.for_action(:create, %{name: "批量分配试卷#{uniq()}", duration_minutes: 60},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    ExamQuestion.create_exam_question!(
      %{exam_id: exam.id, question_id: q1.id, position: 1, score: 50},
      actor: teacher,
      tenant: @tenant
    )

    ExamQuestion.create_exam_question!(
      %{exam_id: exam.id, question_id: q2.id, position: 2, score: 50},
      actor: teacher,
      tenant: @tenant
    )

    {:ok, published} =
      exam
      |> Ash.Changeset.for_update(:publish, %{}, actor: teacher, tenant: @tenant)
      |> Ash.update()

    published
  end
end
