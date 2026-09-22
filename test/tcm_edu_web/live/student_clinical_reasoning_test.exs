defmodule TcmEduWeb.StudentClinicalReasoningTest do
  @moduledoc """
  学生端「全流程临床模拟」（standard_pathway 已配置的病例）PhoenixTest。

  覆盖：
    * 有 standard_pathway 的病例进入会话页时渲染 7 阶段 stepper 与难度标签
    * 问诊阶段仍是聊天 UI，且带「评估问诊并进入下一阶段」按钮
    * 已持久化 CaseStage 时页面刷新恢复进度（当前阶段为下一未完成阶段）
    * 非问诊阶段渲染动作输入面板（每行一条动作）
    * AI 调用失败（未配置 key）时优雅降级：flash 提示、阶段不丢失
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.SimulatedPatient.{Assignment, CaseStage, Patient, Session}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "cr-teacher-#{System.unique_integer([:positive])}@example.com",
          name: "CR Teacher",
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
          email: "cr-student-#{System.unique_integer([:positive])}@example.com",
          name: "CR Student",
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
          name: "进阶胸痛病人",
          complaint: "活动后胸闷胸痛 2 月",
          history: "高血压 8 年，吸烟 30 年",
          personality: "沉默寡言",
          talking_style: "短句",
          key_points: ["问胸痛性质", "问家族史"],
          difficulty: 3,
          difficulty_level: :advanced,
          red_flags: ["意识改变", "血压骤降"],
          standard_pathway: %{
            inquiry: %{must_ask: ["胸痛部位与放射", "持续时间与诱因", "既往史与家族史"]},
            physical_exam: %{must_perform: ["生命体征", "心肺听诊"]},
            auxiliary: %{lab_orders: ["心电图", "肌钙蛋白"], imaging: ["胸部 CT"]},
            diagnosis: %{primary: "冠心病 稳定型心绞痛", evidence: ["活动诱发", "休息缓解"]},
            differential: %{competitors: ["主动脉夹层", "肺栓塞"], how_to_rules_out: ["无撕裂样痛", "无呼吸困难"]},
            treatment: %{plan: ["抗血小板", "调脂", "β受体阻滞剂"], contraindications: ["活动性出血"]},
            follow_up: %{criteria: ["复诊时评估胸痛发作频率"], timeline: "2周复诊"}
          },
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
        "student_name" => "CR Student"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    # AI 调用统一按「未配置 key」降级（本测试不依赖真实 LLM）
    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    {:ok,
     conn: conn, teacher: teacher, student: student, patient: patient, assignment: assignment}
  end

  test "全流程病例进入会话页渲染阶段 stepper 与难度标签", %{
    conn: conn,
    assignment: assignment
  } do
    conn
    |> visit("/simulated-patient")
    |> click_button("#start-#{assignment.id}", "开始 / 继续")
    |> assert_has("p", text: "难度：进阶")
    |> assert_has("span", text: "全流程临床模拟")
    # 问诊阶段仍是聊天 UI + 评估按钮
    |> assert_has("button#evaluate-inquiry", text: "评估问诊并进入下一阶段")
  end

  test "已持久化 CaseStage 时刷新恢复进度，显示下一未完成阶段的面板", %{
    conn: conn,
    teacher: teacher,
    student: student,
    assignment: assignment
  } do
    session =
      conn
      |> visit("/simulated-patient")
      |> click_button("#start-#{assignment.id}", "开始 / 继续")
      |> then(fn _ -> hd(active_sessions(student)) end)

    # 教师/服务端视角把问诊、查体两个阶段标记为已完成
    for {stage, order} <- [{:inquiry, 1}, {:physical_exam, 2}] do
      CaseStage
      |> Ash.Changeset.for_create(
        :create,
        %{
          session_id: session.id,
          stage: stage,
          order: order,
          status: :completed,
          student_actions: [%{type: "action", content: "x"}],
          reasoning_gaps: []
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()
    end

    conn
    |> visit("/simulated-patient/sessions/#{session.id}")
    |> assert_has("button#submit-stage-action", text: "提交并实时对比")
    |> assert_has("label", text: "本阶段动作（每行一条）")
    |> refute_has("button#evaluate-inquiry", text: "评估问诊并进入下一阶段")
  end

  test "问诊发送消息仍然可用且持久化；缺 key 时评估优雅降级", %{
    conn: conn,
    student: student,
    assignment: assignment
  } do
    conn
    |> visit("/simulated-patient")
    |> click_button("#start-#{assignment.id}", "开始 / 继续")
    |> fill_in("向病人提问或陈述", with: "您好，哪里不舒服？")
    |> click_button("#sp-send", "发送")
    |> fill_in("向病人提问或陈述", with: "这种情况多久了？")
    |> click_button("#sp-send", "发送")
    |> fill_in("向病人提问或陈述", with: "您有高血压吗？")
    |> click_button("#sp-send", "发送")

    session = hd(active_sessions(student))
    assert session.turn_count >= 3

    # evaluate-inquiry 在缺 key 时优雅失败（flash 提示，不回退到聊天）
    conn =
      conn
      |> visit("/simulated-patient/sessions/#{session.id}")
      |> click_button("#evaluate-inquiry", "评估问诊并进入下一阶段")

    # 异步 Task 结果需要等待并触发重渲染 —— 有界重试直到 flash 出现
    html =
      Stream.repeatedly(fn ->
        Process.sleep(100)
        Phoenix.LiveViewTest.render(conn.view)
      end)
      |> Stream.take(30)
      |> Enum.find(fn html -> String.contains?(html, "AI 出了错") end)

    assert html != nil, "页面上应出现 AI 出错提示"
  end

  defp active_sessions(student) do
    Session
    |> Ash.Query.for_read(:for_student, %{student_id: student.id},
      actor: student,
      tenant: @tenant
    )
    |> Ash.read!()
    |> Enum.filter(&(&1.status == :active))
  end
end
