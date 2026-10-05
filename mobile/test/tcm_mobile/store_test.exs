defmodule TcmMobile.StoreTest do
  use ExUnit.Case, async: false

  alias TcmMobile.Store

  setup do
    Store.reset()
    :ok
  end

  test "login accepts the demo account and rejects bad credentials" do
    assert Store.logged_in?() == false

    assert {:error, _} = Store.login("student@tcm.edu.cn", "wrong")
    assert {:error, _} = Store.login("", "")

    assert :ok = Store.login("student@tcm.edu.cn", "123456")
    assert Store.logged_in?()
    assert Store.student().name == "李明"
  end

  test "enrolling builds per-course progress" do
    Store.login("student@tcm.edu.cn", "123456")

    assert {:ok, :enrolled} = Store.enroll("c1")
    assert Store.enrolled?("c1")

    progress = Store.progress("c1")
    assert progress.total == 3
    assert progress.percent == 0

    Store.complete_lesson("c1", "c1-l0")
    Store.complete_lesson("c1", "c1-l1")

    assert Store.progress("c1").percent == 67
    assert Store.completed_lesson?("c1", "c1-l0")
  end

  test "submitting an exam records a score and collects wrong answers" do
    Store.login("student@tcm.edu.cn", "123456")

    exam = TcmMobile.Data.Catalog.exam("e1")

    exam.questions
    |> Enum.with_index()
    |> Enum.each(fn {q, _} -> Store.save_answer("e1", q.id, q.answer) end)

    result = Store.submit_exam("e1")
    assert result.score == 100
    assert result.pass?

    mistakes = Store.mistakes()
    assert mistakes == []
  end

  test "wrong answers land in the mistake book" do
    Store.login("student@tcm.edu.cn", "123456")

    exam = TcmMobile.Data.Catalog.exam("e1")
    [w1, w2, w3 | rest] = exam.questions

    # 前 3 题答错，其余答对 → 40 分（< 60 及格线）
    [w1, w2, w3]
    |> Enum.with_index()
    |> Enum.each(fn {q, i} -> Store.save_answer("e1", q.id, rem(q.answer + i + 1, 4)) end)

    Enum.each(rest, fn q -> Store.save_answer("e1", q.id, q.answer) end)

    result = Store.submit_exam("e1")
    refute result.pass?
    assert length(Store.mistakes()) == 3
  end

  test "Q&A chat appends a user and assistant message" do
    Store.login("student@tcm.edu.cn", "123456")

    messages = Store.send_chat("什么是阴阳？")
    assert length(messages) == 2
    assert List.last(messages).role == :assistant
    assert List.last(messages).text =~ "阴阳"
  end

  test "simulated patient session progresses through answers to a grade" do
    Store.login("student@tcm.edu.cn", "123456")

    session = Store.start_sp("sp1")
    assert session.status == :in_progress

    session = Store.send_sp("sp1", "您好，最近感觉怎么样？")
    assert session.shown == 1

    sp = TcmMobile.Data.Catalog.simulated_patient("sp1")
    session = Store.submit_sp("sp1", sp.correct_dialectic)
    assert session.status == :completed
    assert session.grade.correct?
  end
end
