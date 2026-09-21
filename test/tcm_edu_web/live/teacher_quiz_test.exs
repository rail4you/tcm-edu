defmodule TcmEduWeb.TeacherQuizTest do
  @moduledoc """
  Covers the LiveView question bank page (`/teacher/quiz`): banks as a
  selectable list, questions as a paginated table (10 per page) with
  edit/delete operations.
  """
  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.Question
  alias TcmEdu.Quiz.QuestionBank

  @tenant "tenant_default"

  defp teacher_session(conn, teacher) do
    Plug.Test.init_test_session(conn, %{
      "teacher_id" => teacher.id,
      "teacher_role" => "teacher",
      "teacher_tenant" => @tenant,
      "teacher_email" => to_string(teacher.email),
      "teacher_name" => "Table Teacher"
    })
  end

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "quiz-table-#{System.unique_integer([:positive])}@example.com",
          name: "Table Teacher",
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
        %{name: "表格题库", subject: :traditional_chinese_medicine},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    for i <- 1..12 do
      Question.create_question!(
        %{
          bank_id: bank.id,
          type: :single,
          difficulty: 3,
          stem: "题干#{i}",
          options: [
            %{label: "A", text: "甲", correct: true},
            %{label: "B", text: "乙", correct: false}
          ]
        },
        actor: teacher,
        tenant: @tenant
      )
    end

    {:ok, conn: teacher_session(conn, teacher), teacher: teacher, bank: bank}
  end

  test "questions render as paginated table with edit/delete", %{
    conn: conn,
    bank: bank
  } do
    {:ok, view, _} = live(conn, ~p"/teacher/quiz")
    render_click(view, "select-bank", %{"id" => bank.id})
    assigns = :sys.get_state(view.pid).socket.assigns
    assert length(assigns.questions) == 12
    assert assigns.question_page == 1

    html = render(view)
    assert html =~ "共 12 题"
    assert html =~ "第 1 / 2 页"
    # page 1 shows 10 rows
    assert length(Regex.scan(~r/id="question-/, html)) == 10

    # goto page 2 shows remaining 2
    html2 = render_click(view, "goto-page", %{"page" => "2"})
    assert html2 =~ "第 2 / 2 页"
    assert length(Regex.scan(~r/id="question-/, html2)) == 2
    assert html2 =~ "编辑"
    assert html2 =~ "删除"
  end

  test "edit updates stem", %{conn: conn, bank: bank} do
    {:ok, view, _} = live(conn, ~p"/teacher/quiz")
    render_click(view, "select-bank", %{"id" => bank.id})
    [first | _] = :sys.get_state(view.pid).socket.assigns.questions

    render_click(view, "open-edit", %{"id" => first.id})

    html =
      render_submit(view, "submit-question", %{
        "question" => %{
          "type" => "single",
          "difficulty" => "4",
          "stem" => "修改后的题干",
          "explanation" => ""
        },
        "options" => %{
          "0" => %{"text" => "甲", "correct" => "true"},
          "1" => %{"text" => "乙"}
        },
        "op" => "save"
      })

    assert html =~ "题目已更新"
    assert html =~ "修改后的题干"
  end

  test "delete removes question", %{conn: conn, bank: bank} do
    {:ok, view, _} = live(conn, ~p"/teacher/quiz")
    render_click(view, "select-bank", %{"id" => bank.id})
    [first | _] = :sys.get_state(view.pid).socket.assigns.questions

    render_click(view, "confirm-delete", %{"id" => first.id})
    html = render_click(view, "delete", %{})
    assert html =~ "题目已删除"
    assert html =~ "共 11 题"
    refute html =~ first.stem
  end
end
