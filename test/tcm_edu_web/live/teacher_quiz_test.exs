defmodule TcmEduWeb.TeacherQuizTest do
  @moduledoc """
  End-to-end coverage for the question bank page (`/teacher/quiz`) using
  PhoenixTest: banks as a selectable list, questions as a paginated table
  (10 per page) with edit/delete operations.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.Question
  alias TcmEdu.Quiz.QuestionBank

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "quiz-e2e-#{System.unique_integer([:positive])}@example.com",
          name: "Quiz E2E",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    bank =
      QuestionBank
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "E2E题库#{System.unique_integer([:positive])}",
          subject: :traditional_chinese_medicine
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "Quiz E2E"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, bank: bank}
  end

  defp create_questions(teacher, bank, count) do
    for i <- 1..count//1 do
      Question.create_question!(
        %{
          bank_id: bank.id,
          type: :single,
          difficulty: 3,
          stem: "E2E题干#{i}",
          options: [
            %{label: "A", text: "甲", correct: true},
            %{label: "B", text: "乙", correct: false}
          ]
        },
        actor: teacher,
        tenant: @tenant
      )
    end
  end

  defp list_questions(teacher, bank) do
    Question
    |> Ash.Query.for_read(:list_by_bank, %{bank_id: bank.id}, actor: teacher, tenant: @tenant)
    |> Ash.read!()
  end

  test "questions render as paginated table", %{conn: conn, teacher: teacher, bank: bank} do
    create_questions(teacher, bank, 12)

    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> assert_has("p", "共 12 题")
    |> assert_has("p", "第 1 / 2 页")
    |> assert_has("tr[id^='question-']", count: 10)
    |> click_button("下一页")
    |> assert_has("p", "第 2 / 2 页")
    |> assert_has("tr[id^='question-']", count: 2)
  end

  test "edit updates stem and options", %{conn: conn, teacher: teacher, bank: bank} do
    create_questions(teacher, bank, 1)
    [question] = list_questions(teacher, bank)

    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> click_button("#edit-question-#{question.id}", "编辑")
    |> fill_in("题干", with: "修改后的题干", exact: false)
    |> fill_in("#option-text-0", "选项", with: "甲改", exact: false)
    |> uncheck("input[name='options[0][correct]']", "正确答案")
    |> check("input[name='options[1][correct]']", "正确答案")
    |> click_button("保存")
    |> assert_has("p", "题目已更新")
    |> assert_has("td", "修改后的题干")
    |> assert_has("td", "甲改", exact: false)
  end

  test "delete removes the question", %{conn: conn, teacher: teacher, bank: bank} do
    create_questions(teacher, bank, 1)
    [question] = list_questions(teacher, bank)

    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> click_button("#delete-question-#{question.id}", "删除")
    |> click_button("确认删除")
    |> assert_has("p", "题目已删除")
    |> assert_has("p", "共 0 题")
  end

  test "AI-generated questions carry an AI badge", %{conn: conn, teacher: teacher, bank: bank} do
    create_questions(teacher, bank, 1)

    Question.create_question!(
      %{
        bank_id: bank.id,
        type: :judge,
        difficulty: 2,
        stem: "AI 判断题",
        answer: "对",
        tags: ["AI生成"]
      },
      actor: teacher,
      tenant: @tenant
    )

    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> assert_has("tr[id^='question-']", count: 2)
    |> assert_has("span", "AI 生成")
  end

  test "filters questions by type and stem", %{conn: conn, teacher: teacher, bank: bank} do
    create_questions(teacher, bank, 3)

    Question.create_question!(
      %{
        bank_id: bank.id,
        type: :judge,
        difficulty: 2,
        stem: "判断题：肝主疏泄",
        answer: "对"
      },
      actor: teacher,
      tenant: @tenant
    )

    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> assert_has("p", "共 4 题")
    |> click_button("#question-type-judge", "判断")
    |> assert_has("p", "共 1 题")
    |> assert_has("tr[id^='question-']", count: 1)
    |> assert_has("td", "判断题：肝主疏泄")
    |> click_button("#question-type-all", "全部")
    |> assert_has("p", "共 4 题")
    |> fill_in("搜索题干", with: "肝主疏泄")
    |> assert_has("tr[id^='question-']", count: 1)
    |> assert_has("td", "判断题：肝主疏泄")
    |> assert_has("p", "共 1 题")
  end
end
