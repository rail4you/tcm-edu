defmodule TcmEduWeb.StudentSimulatedPatientTest do
  @moduledoc """
  学生端「AI 模拟诊疗」PhoenixTest 覆盖：

    * `/simulated-patient` 能看到教师分配的任务与历史会话
    * 点击「开始 / 继续」会创建/复用 session 并跳到对话页
    * `/simulated-patient/sessions/:id` 能看到 SP 档案与对话 UI
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.SimulatedPatient.{Assignment, Message, Patient, Session}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "sp-stu-teacher-#{System.unique_integer([:positive])}@example.com",
          name: "SP Stu Teacher",
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
          email: "sp-stu-student-#{System.unique_integer([:positive])}@example.com",
          name: "SP Stu Student",
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
          name: "测试病人",
          complaint: "心悸 3 天",
          history: "高血压 5 年",
          personality: "焦虑",
          talking_style: "短句",
          key_points: ["问发作时间", "问既往史"],
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

    assignment =
      Assignment
      |> Ash.Changeset.for_create(
        :create,
        %{
          patient_id: patient.id,
          student_id: student.id,
          assigned_by_id: teacher.id,
          assigned_by_email: to_string(teacher.email),
          status: :assigned
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
        "student_name" => "SP Stu Student"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok,
     conn: conn, teacher: teacher, student: student, patient: patient, assignment: assignment}
  end

  test "student sees assignment on /simulated-patient", %{
    conn: conn,
    patient: patient
  } do
    conn
    |> visit("/simulated-patient")
    |> assert_has("p", text: "教师布置的任务")
    |> assert_has("article[id^=assignment-]", text: patient.name)
  end

  test "starting an assignment creates a session and navigates to chat page", %{
    conn: conn,
    student: student,
    assignment: assignment
  } do
    conn
    |> visit("/simulated-patient")
    |> click_button("#start-#{assignment.id}", "开始 / 继续")
    |> assert_has("details summary", text: "主诉")

    sessions =
      Session
      |> Ash.Query.for_read(:for_student, %{student_id: student.id},
        actor: student,
        tenant: @tenant
      )
      |> Ash.read!()

    assert length(sessions) == 1
    assert hd(sessions).status == :active
    assert hd(sessions).patient_id == assignment.patient_id
  end

  test "student can send a message and it persists even when LLM reply fails", %{
    conn: conn,
    student: student,
    assignment: assignment
  } do
    # 进入会话页
    conn
    |> visit("/simulated-patient")
    |> click_button("#start-#{assignment.id}", "开始 / 继续")
    |> fill_in("向病人提问或陈述", with: "您好，您哪里不舒服？")
    |> click_button("#sp-send", "发送")

    # 学生消息必须已写入数据库（即使 AI 回复因缺 key 失败，消息也要保留）
    session =
      hd(
        Session
        |> Ash.Query.for_read(:for_student, %{student_id: student.id},
          actor: student,
          tenant: @tenant
        )
        |> Ash.read!()
      )

    messages =
      Message
      |> Ash.Query.for_read(:for_session, %{session_id: session.id},
        actor: student,
        tenant: @tenant
      )
      |> Ash.read!()

    assert length(messages) == 1
    assert hd(messages).role == "student"
    assert hd(messages).content =~ "您哪里不舒服"

    # turn_count 已累加
    assert session.turn_count >= 1
  end
end
