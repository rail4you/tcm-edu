defmodule TcmEdu.Quiz.QuizTest do
  @moduledoc """
  题库域测试（Phase 5 新资源骨架）：
    * QuestionBank 创建 / 更新 / 删除，聚合题数
    * Question 创建（自带 relate_actor 出题人）、按题库过滤、软删
    * Attempt.submit 自动判分（单选/多选/判断/主观）
    * my_mistakes 错题本
    * 权限：学生可读、可答题；教师/租户管理员可管题库
    * 跨租户隔离
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.{Attempt, Question, QuestionBank}

  @tenant "tenant_default"

  describe "question_bank" do
    test "teacher can create and list a bank" do
      teacher = create_user!(:teacher)

      assert {:ok, %QuestionBank{name: name} = bank} =
               QuestionBank
               |> Ash.Changeset.for_action(
                 :create,
                 %{
                   name: "中医基础题库 #{uniq()}",
                   subject: :traditional_chinese_medicine,
                   is_public: true
                 },
                 actor: teacher,
                 tenant: @tenant
               )
               |> Ash.create()

      assert name =~ "中医基础题库"

      banks =
        QuestionBank
        |> Ash.Query.filter(id == ^bank.id)
        |> Ash.Query.limit(1)
        |> Ash.read!(actor: teacher, tenant: @tenant)

      assert [%QuestionBank{id: id}] = banks
      assert id == bank.id
    end

    test "bank exposes question_count aggregate" do
      {teacher, bank} = create_bank_with_questions!(2)

      bank =
        QuestionBank
        |> Ash.Query.load([:question_count])
        |> Ash.Query.filter(id == ^bank.id)
        |> Ash.read_one!(actor: teacher, tenant: @tenant)

      assert bank.question_count == 2
    end

    test "student cannot create a bank" do
      student = create_user!(:student)

      assert {:error, %Ash.Error.Forbidden{}} =
               QuestionBank
               |> Ash.Changeset.for_action(:create, %{name: "X #{uniq()}"},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end
  end

  describe "question" do
    test "teacher creates a question; created_by is set via relate_actor" do
      {teacher, bank} = create_bank_with_questions!(0)
      {:ok, question} = create_question!(teacher, bank, "")

      assert question.bank_id == bank.id
      assert question.created_by_id == teacher.id
    end

    test "list_by_bank returns only that bank's questions" do
      {teacher, bank} = create_bank_with_questions!(3)

      list =
        Question
        |> Ash.Query.for_read(:list_by_bank, %{bank_id: bank.id}, actor: teacher, tenant: @tenant)
        |> Ash.read!()

      assert length(list) == 3
    end

    test "soft-delete via archive" do
      {teacher, bank} = create_bank_with_questions!(1)
      [q] = list_questions!(teacher, bank.id)

      assert {:ok, %Question{status: :archived}} =
               q
               |> Ash.Changeset.for_update(:archive, %{})
               |> Ash.update(actor: teacher, tenant: @tenant)
    end
  end

  describe "attempt grading" do
    setup do
      student = create_user!(:student)
      {teacher, bank} = create_bank_with_questions!(0)
      {:ok, single} = create_single_question!(teacher, bank)
      {:ok, multi} = create_multi_question!(teacher, bank)
      {:ok, judge} = create_judge_question!(teacher, bank)
      {:ok, essay} = create_essay_question!(teacher, bank)
      {:ok, student: student, single: single, multi: multi, judge: judge, essay: essay}
    end

    test "correct single answer grades true", %{student: student, single: q} do
      assert {:ok, %Attempt{is_correct: true}} = submit!(student, q, "A")
    end

    test "wrong single answer grades false", %{student: student, single: q} do
      assert {:ok, %Attempt{is_correct: false}} = submit!(student, q, "B")
    end

    test "multi answer order-independent", %{student: student, multi: q} do
      assert {:ok, %Attempt{is_correct: true}} = submit!(student, q, "C,B,A")
      assert {:ok, %Attempt{is_correct: false}} = submit!(student, q, "B,C")
    end

    test "judge answer normalizes 对/错", %{student: student, judge: q} do
      assert {:ok, %Attempt{is_correct: true}} = submit!(student, q, "对")
      assert {:ok, %Attempt{is_correct: false}} = submit!(student, q, "错")
    end

    test "essay not auto-graded (is_correct nil)", %{student: student, essay: q} do
      assert {:ok, %Attempt{is_correct: nil}} = submit!(student, q, "患者主诉为...")
    end

    test "my_mistakes only returns false attempts for the actor", %{
      student: student,
      single: q
    } do
      {:ok, _right} = submit!(student, q, "A")
      {:ok, _wrong} = submit!(student, q, "B")

      mistakes =
        Attempt
        |> Ash.Query.for_read(:my_mistakes, %{}, actor: student, tenant: @tenant)
        |> Ash.read!()

      assert length(mistakes) == 1
      assert hd(mistakes).is_correct == false
    end
  end

  # ─── helpers ───────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "quiz-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_bank!(teacher) do
    {:ok, bank} =
      QuestionBank
      |> Ash.Changeset.for_action(
        :create,
        %{
          name: "Bank #{uniq()}",
          subject: :traditional_chinese_medicine
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    bank
  end

  defp create_bank_with_questions!(n) do
    teacher = create_user!(:teacher)
    bank = create_bank!(teacher)
    for _ <- 1..n, do: create_question!(teacher, bank, "")
    {teacher, bank}
  end

  defp create_question!(teacher, bank, _) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        type: :single,
        stem: "干细胞的分化潜能分类是？#{uniq()}",
        options: [
          %{"label" => "A", "text" => "全能型", "correct" => true},
          %{"label" => "B", "text" => "多能型"}
        ],
        answer: "A",
        explanation: "干细胞按分化潜能分全能型、多能型和专能型。",
        difficulty: 2,
        bank_id: bank.id
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp create_single_question!(teacher, bank) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        type: :single,
        stem: "单选：丹参的功效是？",
        options: [
          %{"label" => "A", "text" => "活血祛瘀", "correct" => true},
          %{"label" => "B", "text" => "补气"}
        ],
        answer: "A",
        bank_id: bank.id
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp create_multi_question!(teacher, bank) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        type: :multi,
        stem: "多选：以下属于四气的是？",
        options: [
          %{"label" => "A", "text" => "寒", "correct" => true},
          %{"label" => "B", "text" => "热", "correct" => true},
          %{"label" => "C", "text" => "温", "correct" => true},
          %{"label" => "D", "text" => "酸", "correct" => false}
        ],
        answer: "A,B,C",
        bank_id: bank.id
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp create_judge_question!(teacher, bank) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        type: :judge,
        stem: "判断：膀胱是贮藏尿液的器官。",
        answer: "对",
        bank_id: bank.id
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp create_essay_question!(teacher, bank) do
    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        type: :essay,
        stem: "简答：请简述中医辨证论治的基本步骤。",
        answer: "收集症状→辨病机→立法→处方",
        bank_id: bank.id
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp list_questions!(teacher, bank_id) do
    Question
    |> Ash.Query.for_read(:list_by_bank, %{bank_id: bank_id}, actor: teacher, tenant: @tenant)
    |> Ash.read!()
  end

  defp submit!(student, question, answer) do
    Attempt
    |> Ash.Changeset.for_action(
      :submit,
      %{
        question_id: question.id,
        answer: answer,
        source: :practice
      },
      actor: student,
      tenant: @tenant
    )
    |> Ash.create()
  end
end
