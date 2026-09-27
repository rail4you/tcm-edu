defmodule TcmEduWeb.StudentExamsTest do
  @moduledoc """
  学生端考试端到端测试（PhoenixTest）：
    * 我的考试列表展示已分配试卷
    * 进入答题页作答并交卷 → 查看结果
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Exam.{Exam, ExamAssignment, ExamQuestion}
  alias TcmEdu.Quiz.{Question, QuestionBank}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "sexam-e2e-#{System.unique_integer([:positive])}@example.com",
          name: "考试老师",
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
          email: "sexam-student-#{System.unique_integer([:positive])}@example.com",
          name: "小王",
          password: "password123",
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    bank =
      QuestionBank.create_question_bank!(%{name: "学生考试题库#{System.unique_integer([:positive])}"},
        actor: teacher,
        tenant: @tenant
      )

    {:ok, single} = create_single!(teacher, bank)
    {:ok, essay} = create_essay!(teacher, bank)
    exam = create_published_exam!(teacher, bank, single, essay)

    {:ok, _assignment} =
      ExamAssignment.assign_exam(%{exam_id: exam.id, student_id: student.id},
        actor: teacher,
        tenant: @tenant
      )

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "student_id" => student.id,
        "student_role" => "student",
        "student_tenant" => @tenant,
        "student_email" => to_string(student.email),
        "student_name" => "小王"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok,
     conn: conn, teacher: teacher, student: student, exam: exam, single: single, essay: essay}
  end

  test "assigned exam appears in my exams and can be taken", %{
    conn: conn,
    exam: exam,
    single: single,
    essay: essay
  } do
    conn
    |> visit("/exams")
    |> assert_has("p", exam.name)
    |> click_link("#take-exam-#{exam.id}", "去答题")
    |> assert_has("p", single.stem)
    |> assert_has("p", essay.stem)
    |> fill_in("#question-#{essay.id} textarea", "作答", with: "先辨证，再立法，最后处方")
    |> assert_has("p", "1 / 2 已答")
    |> click_button("#open-submit-btn", "交卷")
    |> click_button("#confirm-submit-btn", "确认交卷")
    |> assert_path("/exams")
    |> assert_has("p", "交卷成功")
    |> assert_has("span", "待批改")
    |> click_link("#take-exam-#{exam.id}", "等待批改")
    |> assert_has("p", "已交卷，等待教师批改")
    |> refute_has("p", "我的答案")
    |> refute_has("p", "教师批注")
  end

  # ── helpers ───────────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_single!(teacher, bank) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        bank_id: bank.id,
        type: :single,
        stem: "单选：丹参的功效是？#{uniq()}",
        options: [
          %{label: "A", text: "活血祛瘀", correct: true},
          %{label: "B", text: "补气"}
        ],
        answer: "A",
        explanation: "丹参活血祛瘀、凉血消痈。"
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp create_essay!(teacher, bank) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        bank_id: bank.id,
        type: :essay,
        stem: "简答：简述辨证论治步骤？#{uniq()}",
        answer: "收集症状→辨病机→立法→处方",
        explanation: "辨证论治是中医诊治的基本法则。"
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp create_published_exam!(teacher, _bank, single, essay) do
    {:ok, exam} =
      Exam
      |> Ash.Changeset.for_action(:create, %{name: "随堂测验#{uniq()}", duration_minutes: 60},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    ExamQuestion.create_exam_question!(
      %{exam_id: exam.id, question_id: single.id, position: 1, score: 60},
      actor: teacher,
      tenant: @tenant
    )

    ExamQuestion.create_exam_question!(
      %{exam_id: exam.id, question_id: essay.id, position: 2, score: 40},
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
