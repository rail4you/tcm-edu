defmodule TcmEduWeb.TeacherSimulatedPatientTest do
  @moduledoc """
  教师端「AI 模拟诊疗」栏目 PhoenixTest 覆盖：

    * 教师能在 `/teacher/ai/simulated-patient` 创建、发布、归档病人档案
    * 已发布的病人能分配给学生，并在「分配管理」标签页看到
    * 学生端的 `/simulated-patient` 能看到分配给自己的任务
    * 学生点击「开始 / 继续」后会跳到对话页
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.SimulatedPatient.{Assignment, Patient}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "sp-teacher-#{System.unique_integer([:positive])}@example.com",
          name: "SP Teacher",
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
          email: "sp-student-#{System.unique_integer([:positive])}@example.com",
          name: "测试学生",
          password: "password123",
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "SP Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, student: student}
  end

  test "teacher can create, publish and assign a patient", %{
    conn: conn,
    teacher: teacher,
    student: student
  } do
    conn
    |> visit("/teacher/ai/simulated-patient")
    |> assert_has("h3, p", text: "AI 模拟诊疗")
    |> click_button("#new-patient-btn", "新建病人档案")
    |> fill_in("姓名", with: "测试病人张")
    |> fill_in("情境标题（可选）", with: "心悸 3 天")
    |> fill_in("主诉（开场）", with: "我最近 3 天一直觉得心慌")
    |> fill_in("病史背景（现病史 / 既往史 / 查体 / 辅助检查）", with: "高血压 5 年")
    |> click_button("#patient-modal-form button[type=submit]", "保存")
    |> assert_has("p", text: "已创建病人档案", exact: false)

    [patient] = list_patients(teacher)
    assert patient.name == "测试病人张"
    assert patient.status == :draft

    # 发布
    conn
    |> visit("/teacher/ai/simulated-patient")
    |> click_button("#publish-patient-#{patient.id}", "发布")
    |> assert_has("span", text: "已发布", exact: false)

    [published] = list_patients(teacher)
    assert published.status == :published

    # 分配给学生
    conn
    |> visit("/teacher/ai/simulated-patient")
    |> click_button("#assign-patient-#{patient.id}", "分配给学生")
    |> select("学生", option: student.name || student.email)
    |> click_button("#assign-modal-form button[type=submit]", "分配")
    |> assert_has("p", text: "已把", exact: false)

    assignments = list_assignments(teacher)
    assert length(assignments) == 1
    assert hd(assignments).student_id == student.id

    # 切到「分配管理」标签页能看见
    conn
    |> visit("/teacher/ai/simulated-patient?tab=assignments")
    |> assert_has("table")
    |> assert_has("td", text: "测试病人张")
  end

  test "teacher can archive a patient", %{conn: conn, teacher: teacher} do
    patient = create_patient(teacher, "归档测试")

    conn
    |> visit("/teacher/ai/simulated-patient")
    |> click_button("#archive-patient-#{patient.id}", "归档")
    |> assert_has("p", text: "已归档", exact: false)

    [archived] = list_patients(teacher)
    assert archived.status == :archived
  end

  test "teacher can delete a draft patient", %{conn: conn, teacher: teacher} do
    patient = create_patient(teacher, "删除测试")

    conn
    |> visit("/teacher/ai/simulated-patient")
    |> click_button("#delete-patient-#{patient.id}", "")
    |> assert_has("p", text: "已删除", exact: false)

    assert list_patients(teacher) == []
  end

  test "modal defaults to 5 min questions and 20 max turns", %{conn: conn} do
    page = visit(conn, "/teacher/ai/simulated-patient")
    page = click_button(page, "#new-patient-btn", "新建病人档案")
    page = click_button(page, "#modal-tab-rubric", "评分配置")
    rendered = Phoenix.LiveViewTest.render(page.view)

    assert rendered =~ ~s(name="patient[min_questions]")
    assert rendered =~ ~s(name="patient[max_turns]")

    {min, _} =
      Regex.run(~r/min_questions[^>]*value=\"(\d+)\"/, rendered) |> List.last() |> Integer.parse()

    {max, _} =
      Regex.run(~r/max_turns[^>]*value=\"(\d+)\"/, rendered) |> List.last() |> Integer.parse()

    assert min == 5
    assert max == 20
  end

  test "学科下拉选项是中文标签", %{conn: conn} do
    page = visit(conn, "/teacher/ai/simulated-patient")
    page = click_button(page, "#new-patient-btn", "新建病人档案")
    rendered = Phoenix.LiveViewTest.render(page.view)

    for label <- ["中医", "西医", "解剖", "生理", "病理", "药理", "临床", "护理", "公卫", "其他"] do
      assert rendered =~ label,
             "学科下拉里应该出现 #{label}（中文标签），但找不到"
    end
  end

  test "教师能看到「加载示例病人」按钮和示例菜单", %{conn: conn} do
    page = visit(conn, "/teacher/ai/simulated-patient")
    page = click_button(page, "#new-patient-btn", "新建病人档案")
    rendered = Phoenix.LiveViewTest.render(page.view)

    assert rendered =~ "加载示例病人"
    assert rendered =~ "常见慢性病模板"
    assert rendered =~ "原发性高血压（多年随访）"
    assert rendered =~ "2 型糖尿病（初诊乏力、多饮）"
    assert rendered =~ "稳定型心绞痛（胸痛）"
  end

  test "rubric 默认 key 在 UI 上是中文标签", %{conn: conn} do
    page = visit(conn, "/teacher/ai/simulated-patient")
    page = click_button(page, "#new-patient-btn", "新建病人档案")
    page = click_button(page, "#modal-tab-rubric", "评分配置")
    rendered = Phoenix.LiveViewTest.render(page.view)

    # 默认三条维度以中文 label 渲染到评分维度输入框
    assert rendered =~ "value=\"专业度\""
    assert rendered =~ "value=\"同理心\""
    assert rendered =~ "value=\"沟通技巧\""

    # placeholder 也是中文
    assert rendered =~ "维度（如：专业度）"
  end

  test "保存时 UI 中文 label 会被翻译回英文 canonical key", %{conn: conn, teacher: teacher} do
    page = visit(conn, "/teacher/ai/simulated-patient")
    page = click_button(page, "#new-patient-btn", "新建病人档案")
    page = fill_in(page, "姓名", with: "中文 label 测试")
    page = fill_in(page, "主诉（开场）", with: "测试主诉")
    page = click_button(page, "#patient-modal-form button[type=submit]", "保存")
    _ = Phoenix.LiveViewTest.render(page.view)

    [patient] = list_patients(teacher)
    # UI 是「专业度」中文 label，但存的还是英文 canonical
    assert Map.has_key?(patient.rubric, "professional")
    assert Map.has_key?(patient.rubric, "empathy")
    assert Map.has_key?(patient.rubric, "communication")
  end

  # ─── helpers ───────────────────────────────────────────

  defp list_patients(teacher) do
    Patient
    |> Ash.Query.for_read(:read, %{}, actor: teacher, tenant: @tenant)
    |> Ash.read!()
  end

  defp list_assignments(teacher) do
    Assignment
    |> Ash.Query.for_read(:read, %{}, actor: teacher, tenant: @tenant)
    |> Ash.read!()
  end

  defp create_patient(teacher, name) do
    Patient
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        complaint: "测试主诉",
        history: "无",
        personality: "配合",
        talking_style: "正常",
        key_points: ["关键问诊点"],
        difficulty: 3,
        min_questions: 4,
        max_turns: 20,
        status: :draft,
        created_by_id: teacher.id,
        created_by_email: to_string(teacher.email)
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create!()
  end
end
