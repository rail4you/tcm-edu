defmodule TcmEduWeb.StudentClinicalReasoningReportTest do
  @moduledoc "学生端「临床思维报告」PhoenixTest。"

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.SimulatedPatient.{Evaluation, Patient, Session}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "rep-teacher-#{System.unique_integer([:positive])}@example.com",
          name: "REP Teacher",
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
          email: "rep-student-#{System.unique_integer([:positive])}@example.com",
          name: "REP Student",
          password: "password123",
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    patient =
      Patient
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "报告病人",
          complaint: "胸痛 2 月",
          history: "高血压 5 年",
          personality: "焦虑",
          talking_style: "短句",
          key_points: ["问胸痛性质"],
          difficulty: 3,
          min_questions: 3,
          max_turns: 10,
          status: :published,
          created_by_id: teacher.id,
          created_by_email: to_string(teacher.email)
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    session =
      Session
      |> Ash.Changeset.for_create(
        :create,
        %{
          patient_id: patient.id,
          student_id: student.id,
          patient_snapshot: %{"name" => patient.name, "complaint" => patient.complaint},
          status: :completed
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    # 教师侧给这次会话写入带诊断维度的评分
    Evaluation
    |> Ash.Changeset.for_create(
      :create,
      %{
        session_id: session.id,
        patient_id: patient.id,
        student_id: student.id,
        professional_score: 80,
        empathy_score: 70,
        communication_score: 75,
        total_score: Decimal.new("76"),
        grade: :pass,
        diagnosis_score: 82,
        differential_score: 68,
        treatment_score: 75,
        stage_scores: %{
          "inquiry" => 78,
          "physical_exam" => 66,
          "auxiliary" => 72,
          "follow_up" => 0
        },
        feedback: "整体不错",
        weaknesses: ["鉴别诊断不够全面"],
        rubric_snapshot: %{"professional" => 50, "empathy" => 25, "communication" => 25},
        model: "qwen-flash"
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "student_id" => student.id,
        "student_role" => "student",
        "student_tenant" => @tenant,
        "student_email" => to_string(student.email),
        "student_name" => "REP Student"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    {:ok, conn: conn, student: student}
  end

  test "报告页展示六维能力分聚合与生成按钮", %{conn: conn} do
    conn
    |> visit("/simulated-patient/report")
    |> assert_has("h1", text: "我的临床思维能力报告")
    |> assert_has("p", text: "基于 1 次已评分会话")
    # 诊断准确性
    |> assert_has("span", text: "82")
    # 鉴别诊断全面性
    |> assert_has("span", text: "68")
    |> assert_has("button#generate-report", text: "生成本期 AI 报告")
  end

  test "从模拟诊疗列表可进入报告页", %{conn: conn} do
    conn
    |> visit("/simulated-patient")
    |> assert_has("a", text: "临床思维报告")
    |> click_link("临床思维报告")
    |> assert_has("h1", text: "我的临床思维能力报告")
  end
end
