defmodule TcmEdu.AI.QuizValidatorTest do
  @moduledoc """
  `TcmEdu.AI.QuizValidator` 纯函数测试：题型 / 选项 / 答案规则与归一化。
  """

  use ExUnit.Case, async: true

  alias TcmEdu.AI.QuizValidator

  describe "validate_items/2" do
    test "accepts a valid single-choice question and normalizes answer" do
      data = [
        %{
          "type" => "single",
          "stem" => "手太阴肺经的起始穴是？",
          "options" => [
            %{"label" => "A", "text" => "中府", "correct" => true},
            %{"label" => "B", "text" => "云门", "correct" => false},
            %{"label" => "C", "text" => "天府", "correct" => false}
          ],
          "answer" => "A",
          "explanation" => "肺经起于中焦，下络大肠，还循胃口，上膈属肺，起始穴中府。",
          "difficulty" => 2,
          "knowledge_points" => ["肺经", "腧穴"]
        }
      ]

      assert {:ok, [attrs]} = QuizValidator.validate_items(data)
      assert attrs.type == :single
      assert attrs.stem == "手太阴肺经的起始穴是？"
      assert attrs.answer == "A"
      assert Enum.map(attrs.options, & &1.label) == ["A", "B", "C"]
      assert attrs.difficulty == 2
      assert attrs.knowledge_points == ["肺经", "腧穴"]
    end

    test "multi question joins correct labels and strips option prefixes" do
      data = [
        %{
          "type" => "multi",
          "stem" => "下列属于五输穴的有？",
          "options" => [
            %{"text" => "A. 井穴", "correct" => true},
            %{"text" => "B、荥穴", "correct" => true},
            %{"text" => "C. 原穴", "correct" => false}
          ],
          "difficulty" => 4
        }
      ]

      assert {:ok, [attrs]} = QuizValidator.validate_items(data)
      assert attrs.type == :multi
      assert attrs.answer == "AB"
      assert Enum.map(attrs.options, & &1.text) == ["井穴", "荥穴", "原穴"]
    end

    test "judge question normalizes answer variants" do
      for raw <- ["对", "正确", "true", "是"] do
        assert {:ok, [%{type: :judge, answer: "对", options: []}]} =
                 QuizValidator.validate_items([
                   %{"type" => "judge", "stem" => "S", "answer" => raw}
                 ])
      end

      assert {:ok, [%{answer: "错"}]} =
               QuizValidator.validate_items([
                 %{"type" => "judge", "stem" => "S", "answer" => "错误"}
               ])
    end

    test "essay question keeps reference answer and drops options" do
      data = [%{"type" => "essay", "stem" => "简述阴阳学说。", "answer" => "阴阳对立制约…"}]

      assert {:ok, [%{type: :essay, answer: "阴阳对立制约…", options: []}]} =
               QuizValidator.validate_items(data)
    end

    test "single with two correct options fails" do
      data = [
        %{
          "type" => "single",
          "stem" => "S",
          "options" => [
            %{"text" => "甲", "correct" => true},
            %{"text" => "乙", "correct" => true}
          ]
        }
      ]

      assert {:error, reason} = QuizValidator.validate_items(data)
      assert reason =~ "单选"
    end

    test "essay without answer fails" do
      assert {:error, reason} =
               QuizValidator.validate_items([%{"type" => "essay", "stem" => "S"}])

      assert reason =~ "参考答案"
    end

    test "judge with invalid answer fails" do
      assert {:error, reason} =
               QuizValidator.validate_items([
                 %{"type" => "judge", "stem" => "S", "answer" => "也许"}
               ])

      assert reason =~ "判断题"
    end

    test "empty list and non-list input fail" do
      assert {:error, _} = QuizValidator.validate_items([])
      assert {:error, _} = QuizValidator.validate_items("not json")
      assert {:error, _} = QuizValidator.validate_items(42)
    end

    test "single object (not array) is accepted for compatibility" do
      assert {:ok, [%{type: :judge}]} =
               QuizValidator.validate_items(%{"type" => "judge", "stem" => "S", "answer" => "对"})
    end

    test "difficulty is clamped and knowledge points split from string" do
      data = [
        %{
          "type" => "single",
          "stem" => "S",
          "options" => [
            %{"text" => "甲", "correct" => true},
            %{"text" => "乙", "correct" => false}
          ],
          "difficulty" => 99,
          "knowledge_points" => "肺经，腧穴定位"
        }
      ]

      assert {:ok, [attrs]} = QuizValidator.validate_items(data)
      assert attrs.difficulty == 5
      assert attrs.knowledge_points == ["肺经", "腧穴定位"]
    end
  end
end
