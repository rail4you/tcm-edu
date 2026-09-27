defmodule TcmEdu.Exam.ExamTest do
  @moduledoc """
  考试域测试：
    * 试卷 CRUD / 发布 / 关闭
    * 手工组卷（ExamQuestion 分值 / 顺序 / 去重）
    * 批量分配（仅已发布、跳过已分配）
    * 学生答题自动判分（客观题）+ 交卷计分
    * 教师批改简答题 → 总分更新
    * 权限：学生只能读已发布试卷、只能答自己的分配；教师可管理
    * AI 组卷 ExamComposer 纯逻辑
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.AI.ExamComposer
  alias TcmEdu.Exam.{Exam, ExamAssignment, ExamQuestion, ExamResponse}
  alias TcmEdu.Quiz.{Question, QuestionBank}

  @tenant "tenant_default"

  describe "exam lifecycle" do
    test "teacher creates a draft exam, publishes and closes it" do
      teacher = create_user!(:teacher)
      {:ok, exam} = create_exam!(teacher, "期中考试")

      assert exam.status == :draft
      assert exam.source == :manual
      assert exam.created_by_id == teacher.id

      assert {:ok, %Exam{status: :published} = published} = publish!(exam, teacher)
      assert {:ok, %Exam{status: :closed}} = close!(published, teacher)
    end

    test "student cannot create or update exams" do
      student = create_user!(:student)

      assert {:error, %Ash.Error.Forbidden{}} =
               Exam
               |> Ash.Changeset.for_action(:create, %{name: "作弊 #{uniq()}"},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end

    test "student can only read published exams" do
      teacher = create_user!(:teacher)
      student = create_user!(:student)
      {:ok, draft} = create_exam!(teacher, "草稿卷")
      {:ok, published} = create_exam!(teacher, "公开卷")
      {:ok, _} = publish!(published, teacher)

      assert [] =
               Exam
               |> Ash.Query.filter(id == ^draft.id)
               |> Ash.read(actor: student, tenant: @tenant)
               |> elem(1)

      assert [%Exam{id: id}] =
               Exam
               |> Ash.Query.filter(id == ^published.id)
               |> Ash.read(actor: student, tenant: @tenant)
               |> elem(1)

      assert id == published.id
    end
  end

  describe "manual composition" do
    setup do
      teacher = create_user!(:teacher)
      bank = create_bank!(teacher)
      {:ok, single} = create_question!(teacher, bank, :single, "单选：丹参功效")
      {:ok, judge} = create_question!(teacher, bank, :judge, "判断：膀胱藏尿")
      {:ok, essay} = create_question!(teacher, bank, :essay, "简答：辨证论治步骤")
      {:ok, exam} = create_exam!(teacher, "组卷测试")

      {:ok,
       %{teacher: teacher, bank: bank, single: single, judge: judge, essay: essay, exam: exam}}
    end

    test "add questions with scores and positions", %{
      teacher: teacher,
      exam: exam,
      single: single,
      judge: judge
    } do
      eq1 =
        ExamQuestion.create_exam_question!(
          %{
            exam_id: exam.id,
            question_id: single.id,
            position: 1,
            score: 20
          },
          actor: teacher,
          tenant: @tenant
        )

      eq2 =
        ExamQuestion.create_exam_question!(
          %{
            exam_id: exam.id,
            question_id: judge.id,
            position: 2,
            score: 10
          },
          actor: teacher,
          tenant: @tenant
        )

      assert eq1.exam_id == exam.id
      assert eq2.position == 2

      loaded =
        Exam
        |> Ash.Query.load([:exam_questions, :total_questions, :total_score])
        |> Ash.Query.filter(id == ^exam.id)
        |> Ash.read_one!(actor: teacher, tenant: @tenant)

      assert loaded.total_questions == 2
      assert Decimal.to_string(loaded.total_score) == "30"
      assert [%ExamQuestion{position: 1}, %ExamQuestion{position: 2}] = loaded.exam_questions
    end

    test "same question cannot be added twice (upsert)", %{
      teacher: teacher,
      exam: exam,
      single: single
    } do
      attrs = %{exam_id: exam.id, question_id: single.id, position: 1, score: 20}

      assert {:ok, _} =
               ExamQuestion
               |> Ash.Changeset.for_action(:create, attrs, actor: teacher, tenant: @tenant)
               |> Ash.create()

      assert {:ok, _} =
               ExamQuestion
               |> Ash.Changeset.for_action(:create, attrs, actor: teacher, tenant: @tenant)
               |> Ash.create()

      assert length(
               ExamQuestion
               |> Ash.Query.filter(exam_id == ^exam.id)
               |> Ash.read!(actor: teacher, tenant: @tenant)
             ) == 1
    end

    test "student cannot compose (cannot create exam_question)", %{
      exam: exam,
      single: single
    } do
      student = create_user!(:student)

      assert {:error, %Ash.Error.Forbidden{}} =
               ExamQuestion
               |> Ash.Changeset.for_action(
                 :create,
                 %{
                   exam_id: exam.id,
                   question_id: single.id,
                   position: 1,
                   score: 20
                 },
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end
  end

  describe "bulk assign" do
    setup do
      teacher = create_user!(:teacher)
      bank = create_bank!(teacher)
      {:ok, single} = create_question!(teacher, bank, :single, "单选A")
      {:ok, judge} = create_question!(teacher, bank, :judge, "判断B")
      {:ok, exam} = create_exam!(teacher, "分配测试")
      add_question!(teacher, exam, single, 1, 60)
      add_question!(teacher, exam, judge, 2, 40)
      student1 = create_user!(:student)
      student2 = create_user!(:student)

      {:ok,
       %{
         teacher: teacher,
         exam: exam,
         single: single,
         judge: judge,
         student1: student1,
         student2: student2
       }}
    end

    test "draft exam cannot be assigned", %{teacher: teacher, exam: exam, student1: student1} do
      assert {:error, error} =
               Exam.bulk_assign(%{exam_id: exam.id, student_ids: [student1.id]},
                 actor: teacher,
                 tenant: @tenant
               )

      assert err_message(error) =~ "尚未发布"
    end

    test "publish then bulk assign skips already-assigned", %{
      teacher: teacher,
      exam: exam,
      student1: student1,
      student2: student2
    } do
      {:ok, _} = publish!(exam, teacher)

      assert {:ok, %{assigned: 2, skipped: 0}} =
               Exam.bulk_assign(%{exam_id: exam.id, student_ids: [student1.id, student2.id]},
                 actor: teacher,
                 tenant: @tenant
               )

      assert {:ok, %{assigned: 0, skipped: 2}} =
               Exam.bulk_assign(%{exam_id: exam.id, student_ids: [student1.id, student2.id]},
                 actor: teacher,
                 tenant: @tenant
               )

      assert length(
               ExamAssignment
               |> Ash.Query.filter(exam_id == ^exam.id)
               |> Ash.read!(actor: teacher, tenant: @tenant)
             ) == 2
    end

    test "student cannot bulk assign", %{
      teacher: teacher,
      exam: exam,
      student1: student1,
      student2: student2
    } do
      {:ok, _} = publish!(exam, teacher)

      assert {:error, _} =
               Exam.bulk_assign(%{exam_id: exam.id, student_ids: [student1.id, student2.id]},
                 actor: student1,
                 tenant: @tenant
               )
    end
  end

  describe "student answering" do
    setup do
      teacher = create_user!(:teacher)
      bank = create_bank!(teacher)
      {:ok, single} = create_question!(teacher, bank, :single, "单选：丹参功效")
      {:ok, judge} = create_question!(teacher, bank, :judge, "判断：膀胱藏尿")
      {:ok, essay} = create_question!(teacher, bank, :essay, "简答：辨证论治")
      {:ok, exam} = create_exam!(teacher, "答题测试")
      add_question!(teacher, exam, single, 1, 40)
      add_question!(teacher, exam, judge, 2, 30)
      add_question!(teacher, exam, essay, 3, 30)
      {:ok, _} = publish!(exam, teacher)
      student = create_user!(:student)

      {:ok, assignment} =
        ExamAssignment.assign_exam(%{exam_id: exam.id, student_id: student.id},
          actor: teacher,
          tenant: @tenant
        )

      {:ok,
       %{
         teacher: teacher,
         student: student,
         single: single,
         judge: judge,
         essay: essay,
         exam: exam,
         assignment: assignment
       }}
    end

    test "objective responses auto-grade; assignment turns in_progress", %{
      student: student,
      single: single,
      judge: judge,
      assignment: assignment
    } do
      {:ok, resp1} =
        ExamResponse.submit_exam_response(
          %{
            assignment_id: assignment.id,
            question_id: single.id,
            answer: "A"
          },
          actor: student,
          tenant: @tenant
        )

      assert resp1.is_correct == true
      assert Decimal.to_string(resp1.score) == "40"

      {:ok, resp2} =
        ExamResponse.submit_exam_response(
          %{
            assignment_id: assignment.id,
            question_id: single.id,
            answer: "B"
          },
          actor: student,
          tenant: @tenant
        )

      assert resp2.is_correct == false
      assert Decimal.to_string(resp2.score) == "0"

      {:ok, resp3} =
        ExamResponse.submit_exam_response(
          %{
            assignment_id: assignment.id,
            question_id: judge.id,
            answer: "对"
          },
          actor: student,
          tenant: @tenant
        )

      assert resp3.is_correct == true

      started =
        ExamAssignment |> Ash.get!(assignment.id, actor: student, tenant: @tenant)

      assert started.status == :in_progress
      assert started.started_at != nil
    end

    test "essay response is not auto-graded", %{
      student: student,
      essay: essay,
      assignment: assignment
    } do
      {:ok, resp} =
        ExamResponse.submit_exam_response(
          %{
            assignment_id: assignment.id,
            question_id: essay.id,
            answer: "收集症状→辨病机→立法→处方"
          },
          actor: student,
          tenant: @tenant
        )

      assert resp.is_correct == nil
      assert resp.score == nil
      assert resp.graded == false
    end

    test "student cannot answer someone else's assignment", %{
      student: _student,
      single: single,
      assignment: assignment
    } do
      other = create_user!(:student)

      assert {:error, error} =
               ExamResponse.submit_exam_response(
                 %{
                   assignment_id: assignment.id,
                   question_id: single.id,
                   answer: "A"
                 },
                 actor: other,
                 tenant: @tenant
               )

      assert err_message(error) =~ "只能作答分配给自己的考试"
    end

    test "cannot answer after submit", %{
      teacher: _teacher,
      student: student,
      single: single,
      assignment: assignment
    } do
      {:ok, _} =
        ExamResponse.submit_exam_response(
          %{
            assignment_id: assignment.id,
            question_id: single.id,
            answer: "A"
          },
          actor: student,
          tenant: @tenant
        )

      {:ok, _} = submit_assignment!(assignment, student)

      assert {:error, error} =
               ExamResponse.submit_exam_response(
                 %{
                   assignment_id: assignment.id,
                   question_id: single.id,
                   answer: "B"
                 },
                 actor: student,
                 tenant: @tenant
               )

      assert err_message(error) =~ "已交卷"
    end

    test "submit locks objective score; teacher grades essay", %{
      teacher: teacher,
      student: student,
      single: single,
      judge: judge,
      essay: essay,
      assignment: assignment
    } do
      submit!(student, assignment, single, "A")
      submit!(student, assignment, judge, "对")
      submit!(student, assignment, essay, "收集症状→辨病机")

      {:ok, submitted} = submit_assignment!(assignment, student)
      assert submitted.status == :submitted
      assert Decimal.to_string(submitted.objective_score) == "70"
      assert Decimal.to_string(submitted.total_score) == "70"

      # 教师批改简答题
      response =
        ExamResponse
        |> Ash.Query.filter(assignment_id == ^assignment.id and question_id == ^essay.id)
        |> Ash.read_one!(actor: teacher, tenant: @tenant)

      {:ok, _} =
        response
        |> Ash.Changeset.for_update(:grade_essay, %{score: 25, comment: "条理清晰"},
          actor: teacher,
          tenant: @tenant
        )
        |> Ash.update()

      # 逐题批改后总分实时更新（状态仍为 submitted）
      partial = ExamAssignment |> Ash.get!(assignment.id, actor: teacher, tenant: @tenant)
      assert Decimal.to_string(partial.essay_score) == "25"
      assert Decimal.to_string(partial.total_score) == "95"

      # 教师最终批改 → graded
      {:ok, graded} = grade_assignment!(assignment, teacher)
      assert graded.status == :graded
      assert graded.graded_at != nil
    end
  end

  describe "student reads own assignments" do
    test "my_exams only returns the actor's assignments" do
      teacher = create_user!(:teacher)
      bank = create_bank!(teacher)
      {:ok, q} = create_question!(teacher, bank, :single, "单选")
      {:ok, exam} = create_exam!(teacher, "我的考试")
      add_question!(teacher, exam, q, 1, 100)
      {:ok, _} = publish!(exam, teacher)
      student = create_user!(:student)
      other = create_user!(:student)

      {:ok, _} =
        ExamAssignment.assign_exam(%{exam_id: exam.id, student_id: student.id},
          actor: teacher,
          tenant: @tenant
        )

      mine =
        ExamAssignment
        |> Ash.Query.for_read(:my_exams, %{}, actor: student, tenant: @tenant)
        |> Ash.read!()

      assert length(mine) == 1
      assert hd(mine).student_id == student.id

      assert [] =
               ExamAssignment
               |> Ash.Query.for_read(:my_exams, %{}, actor: other, tenant: @tenant)
               |> Ash.read!()
    end
  end

  describe "ExamComposer" do
    defp candidate(id, type, difficulty, kps \\ []) do
      %{id: id, stem: "题#{id}", type: type, difficulty: difficulty, knowledge_points: kps}
    end

    test "select respects type whitelist" do
      candidates = [
        candidate("1", :single, 3),
        candidate("2", :judge, 3),
        candidate("3", :essay, 3)
      ]

      assert {:ok, picked} = ExamComposer.select(candidates, count: 5, question_types: ["single"])
      assert Enum.map(picked, & &1.id) == ["1"]
    end

    test "select round-robins across types and caps at count" do
      candidates =
        Enum.map(1..6, &candidate("#{&1}", if(rem(&1, 2) == 0, do: :judge, else: :single), 3))

      assert {:ok, picked} =
               ExamComposer.select(candidates,
                 count: 4,
                 question_types: ["single", "judge"]
               )

      ids = Enum.map(picked, & &1.id)
      assert length(ids) == 4
      assert length(Enum.filter(picked, &(&1.type == "single"))) == 2
      assert length(Enum.filter(picked, &(&1.type == "judge"))) == 2
    end

    test "difficulty closeness preferred" do
      candidates = [
        candidate("easy", :single, 1),
        candidate("mid", :single, 3),
        candidate("hard", :single, 5)
      ]

      assert {:ok, picked} =
               ExamComposer.select(candidates,
                 count: 1,
                 question_types: ["single"],
                 difficulty: 5
               )

      assert hd(picked).id == "hard"
    end

    test "knowledge point match preferred" do
      candidates = [
        candidate("a", :single, 3, ["肺经"]),
        candidate("b", :single, 3, ["肝经"])
      ]

      assert {:ok, picked} =
               ExamComposer.select(candidates,
                 count: 1,
                 question_types: ["single"],
                 knowledge_points: ["肺经"]
               )

      assert hd(picked).id == "a"
    end

    test "validate rejects unknown ids" do
      candidates = [candidate("1", :single, 3)]

      assert {:error, _} = ExamComposer.validate(candidates, ["1", "999"])
      assert {:error, _} = ExamComposer.validate(candidates, [])
      assert {:ok, ["1", "1"] |> Enum.uniq()} == ExamComposer.validate(candidates, ["1", "1"])
    end

    test "distribute_scores is exact" do
      scores = ExamComposer.distribute_scores(["a", "b", "c"], 100)

      total =
        scores
        |> Map.values()
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      assert Decimal.to_string(total) == "100.00"
      assert length(Map.keys(scores)) == 3
    end
  end

  # ─── helpers ───────────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp err_message(error) do
    Exception.message(error)
  rescue
    _ -> inspect(error)
  end

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "exam-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_bank!(teacher) do
    {:ok, bank} =
      QuestionBank
      |> Ash.Changeset.for_action(:create, %{name: "ExamBank #{uniq()}"},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    bank
  end

  defp create_question!(teacher, bank, type, stem) do
    attrs = %{bank_id: bank.id, type: type, stem: "#{stem}？#{uniq()}"}

    attrs =
      case type do
        :single ->
          Map.merge(attrs, %{
            options: [
              %{"label" => "A", "text" => "活血祛瘀", "correct" => true},
              %{"label" => "B", "text" => "补气"}
            ],
            answer: "A"
          })

        :judge ->
          Map.merge(attrs, %{options: [], answer: "对"})

        :essay ->
          Map.merge(attrs, %{options: [], answer: "收集症状→辨病机→立法→处方"})
      end

    Question
    |> Ash.Changeset.for_action(:create, attrs, actor: teacher, tenant: @tenant)
    |> Ash.create()
  end

  defp create_exam!(teacher, name) do
    Exam
    |> Ash.Changeset.for_action(
      :create,
      %{
        name: "#{name}#{uniq()}",
        subject: :traditional_chinese_medicine,
        duration_minutes: 60
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp publish!(exam, teacher) do
    exam
    |> Ash.Changeset.for_update(:publish, %{}, actor: teacher, tenant: @tenant)
    |> Ash.update()
  end

  defp close!(exam, teacher) do
    exam
    |> Ash.Changeset.for_update(:close, %{}, actor: teacher, tenant: @tenant)
    |> Ash.update()
  end

  defp add_question!(teacher, exam, question, position, score) do
    {:ok, _} =
      ExamQuestion
      |> Ash.Changeset.for_action(
        :create,
        %{
          exam_id: exam.id,
          question_id: question.id,
          position: position,
          score: score
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()
  end

  defp submit!(student, assignment, question, answer) do
    {:ok, _} =
      ExamResponse.submit_exam_response(
        %{
          assignment_id: assignment.id,
          question_id: question.id,
          answer: answer
        },
        actor: student,
        tenant: @tenant
      )
  end

  defp submit_assignment!(assignment, student) do
    fresh = ExamAssignment |> Ash.get!(assignment.id, actor: student, tenant: @tenant)

    fresh
    |> Ash.Changeset.for_update(:submit, %{}, actor: student, tenant: @tenant)
    |> Ash.update()
  end

  defp grade_assignment!(assignment, teacher) do
    fresh = ExamAssignment |> Ash.get!(assignment.id, actor: teacher, tenant: @tenant)

    fresh
    |> Ash.Changeset.for_update(:grade, %{}, actor: teacher, tenant: @tenant)
    |> Ash.update()
  end
end
