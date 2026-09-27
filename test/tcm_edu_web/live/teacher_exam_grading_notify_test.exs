defmodule TcmEduWeb.TeacherExamGradingNotifyTest do
  @moduledoc """
  教师完成批改 → 学生收到 `:exam_graded` 通知（PhoenixTest）：
    * 批改后 flash 提示已通知
    * 学生通知中心可见该通知（含查看成绩入口）
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Exam.{Exam, ExamAssignment, ExamQuestion}
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Quiz.{Question, QuestionBank}

  @tenant "tenant_default"

  setup %{conn: _conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "grade-notify-t-#{System.unique_integer([:positive])}@example.com",
          name: "批改老师",
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
          email: "grade-notify-s-#{System.unique_integer([:positive])}@example.com",
          name: "考生",
          password: "password123",
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    bank =
      QuestionBank.create_question_bank!(%{name: "批改通知题库#{System.unique_integer([:positive])}"},
        actor: teacher,
        tenant: @tenant
      )

    {:ok, question} =
      Question
      |> Ash.Changeset.for_action(
        :create,
        %{
          bank_id: bank.id,
          type: :single,
          stem: "单选：甘草的功效是？#{System.unique_integer([:positive])}",
          options: [
            %{label: "A", text: "补气缓急", correct: true},
            %{label: "B", text: "活血"}
          ],
          answer: "A"
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    {:ok, exam} =
      Exam
      |> Ash.Changeset.for_action(
        :create,
        %{name: "批改通知试卷#{System.unique_integer([:positive])}", duration_minutes: 60},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    ExamQuestion.create_exam_question!(
      %{exam_id: exam.id, question_id: question.id, position: 1, score: 100},
      actor: teacher,
      tenant: @tenant
    )

    {:ok, exam} =
      exam
      |> Ash.Changeset.for_update(:publish, %{}, actor: teacher, tenant: @tenant)
      |> Ash.update()

    {:ok, assignment} =
      ExamAssignment.assign_exam(%{exam_id: exam.id, student_id: student.id},
        actor: teacher,
        tenant: @tenant
      )

    # 学生作答并交卷
    {:ok, _} =
      assignment
      |> Ash.Changeset.for_update(:submit, %{}, actor: student, tenant: @tenant)
      |> Ash.update()

    {:ok, teacher: teacher, student: student, exam: exam, assignment: assignment}
  end

  test "完成批改后学生收到通知", %{
    conn: conn,
    teacher: teacher,
    student: student,
    exam: exam,
    assignment: assignment
  } do
    teacher_conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "批改老师"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    teacher_conn
    |> visit("/teacher/exams/#{exam.id}/results")
    |> click_button("#grade-assignment-#{assignment.id}", "批改")
    |> click_button("#finish-grading-btn", "完成批改")
    |> assert_has("p", "批改完成，已通知学生查看成绩")

    # 学生侧：通知已落库
    {:ok, notifications} =
      Notification
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.read()

    assert Enum.any?(notifications, &(&1.type == :exam_graded and &1.recipient_id == student.id))

    student_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "student_id" => student.id,
        "student_role" => "student",
        "student_tenant" => @tenant,
        "student_email" => to_string(student.email),
        "student_name" => "考生"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    student_conn
    |> visit("/notifications")
    |> assert_has("p", "试卷已批改")
    |> assert_has("a", "查看成绩")
  end
end
