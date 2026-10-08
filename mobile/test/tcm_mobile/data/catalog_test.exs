defmodule TcmMobile.Data.CatalogTest do
  use ExUnit.Case, async: true

  alias TcmMobile.Data.{Catalog, Questions}

  test "courses cover the five TCM categories with unique ids" do
    courses = Catalog.courses()
    assert length(courses) >= 8
    assert length(Enum.uniq_by(courses, & &1.id)) == length(courses)

    cat_ids = courses |> Enum.map(& &1.category) |> Enum.uniq()
    assert length(cat_ids) == 5
  end

  test "every course has lessons with stable ids" do
    for course <- Catalog.courses() do
      lessons = Catalog.lessons(course.id)
      assert lessons != []
      assert length(Enum.uniq_by(lessons, & &1.id)) == length(lessons)
      assert Enum.all?(lessons, &(&1.course_id == course.id))
    end
  end

  test "every lesson has text content" do
    for course <- Catalog.courses(),
        lesson <- Catalog.lessons(course.id) do
      assert is_list(Catalog.lesson_content(lesson.id))
      assert length(Catalog.lesson_content(lesson.id)) > 0
    end
  end

  test "lesson quiz answers resolve from the question bank" do
    quizzes = [
      Catalog.lesson_quiz("c1-l2"),
      Catalog.lesson_quiz("c2-l2"),
      Catalog.lesson_quiz("c9-l2")
    ]

    assert Enum.all?(quizzes, &(not is_nil(&1)))
    assert Enum.all?(quizzes, &(&1.answer < length(&1.options)))
  end

  test "exams reference valid questions with typed answers" do
    for exam <- Catalog.exams() do
      assert Enum.count(exam.questions) >= 5
      assert exam.pass_score == 60
      assert exam.mode in [:quiz, :exam]

      for q <- exam.questions do
        case Questions.type(q) do
          :single ->
            assert match?([_, _, _, _], q.options)
            assert q.answer in 0..3

          type ->
            assert type in [:fill, :essay]
            assert q.options == []
            assert is_binary(q.answer) and String.trim(q.answer) != ""
        end
      end
    end
  end

  test "the question bank covers choice, fill and essay questions" do
    types = Questions.all() |> Enum.map(&Questions.type/1) |> Enum.uniq()

    assert :single in types
    assert :fill in types
    assert :essay in types
  end

  test "simulated patients define dialectic options and a correct answer" do
    for sp <- Catalog.simulated_patients() do
      assert sp.correct_dialectic < length(sp.dialectic_options)
      assert length(sp.answers) > 0
      assert sp.evaluation[:syndrome]
    end
  end

  test "question bank is internally consistent" do
    assert length(Questions.all()) >= 18
  end
end
