defmodule TcmMobile.Store do
  @moduledoc """
  学员端状态仓库 —— 单进程持有当前登录学员、选课、进度、错题、通知、
  学习问答、模拟患者会话与测验作答记录。

  界面通过 `TcmMobile.Api` 访问（本地数据层 = 本仓库 + `Catalog`）；
  后端接 JSON API 后由 `Api` 切换到远程读取，界面不感知。
  """

  use GenServer

  alias TcmMobile.Data.{Ai, Catalog, Questions}

  @name __MODULE__

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(_opts \\ %{}), do: GenServer.start_link(__MODULE__, %{}, name: @name)

  @doc "重置为初始状态（测试隔离用）。"
  def reset, do: GenServer.call(@name, :reset)

  def student, do: call(:student)
  def logged_in?, do: call(:logged_in?)
  def login(email, password), do: call({:login, email, password})
  def logout, do: call(:logout)
  @doc "远程登录 / 会话恢复时，把后端返回的学员身份写入会话。"
  def set_session(student), do: call({:set_session, student})

  def enroll(course_id), do: call({:enroll, course_id})
  def enrolled?(course_id), do: call({:enrolled?, course_id})
  def complete_lesson(course_id, lesson_id), do: call({:complete_lesson, course_id, lesson_id})
  def progress(course_id), do: call({:progress, course_id})

  def completed_lesson?(course_id, lesson_id),
    do: call({:completed_lesson?, course_id, lesson_id})

  def my_courses, do: call(:my_courses)
  def my_stats, do: call(:my_stats)

  def mistakes, do: call(:mistakes)
  def clear_mistake(id), do: call({:clear_mistake, id})

  def notifications, do: call(:notifications)
  def unread_count, do: call(:unread_count)
  def mark_notifications_read, do: call(:mark_notifications_read)

  def chat_messages, do: call(:chat_messages)
  def send_chat(text), do: call({:send_chat, text})

  def sp_sessions, do: call(:sp_sessions)
  def sp_session(patient_id), do: call({:sp_session, patient_id})
  def start_sp(patient_id), do: call({:start_sp, patient_id})
  def send_sp(patient_id, text), do: call({:send_sp, patient_id, text})
  def submit_sp(patient_id, choice), do: call({:submit_sp, patient_id, choice})

  def mdt_messages(room_id), do: call({:mdt_messages, room_id})
  def send_mdt(room_id, text), do: call({:send_mdt, room_id, text})

  def exam_attempt(exam_id), do: call({:exam_attempt, exam_id})
  def exam_result(exam_id), do: call({:exam_result, exam_id})

  def save_answer(exam_id, question_id, value),
    do: call({:save_answer, exam_id, question_id, value})

  def submit_exam(exam_id), do: call({:submit_exam, exam_id})

  def downloads, do: call(:downloads)
  def toggle_download(id), do: call({:toggle_download, id})

  defp call(msg), do: GenServer.call(@name, msg)

  # ── Server ──────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, initial_state()}
  end

  defp initial_state do
    notifications = Enum.map(Catalog.notifications(), & &1)
    downloads = Map.new(Catalog.resources(), &{&1.id, false})

    %{
      student: nil,
      enrollments: %{},
      mistakes: [],
      notifications: notifications,
      downloads: downloads,
      chat_messages: [],
      sp_sessions: %{},
      mdt_messages: %{},
      exam_attempts: %{}
    }
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, initial_state()}
  end

  @impl true
  def handle_call(:student, _from, state), do: {:reply, state.student, state}
  def handle_call(:logged_in?, _from, state), do: {:reply, state.student != nil, state}

  def handle_call({:login, email, password}, _from, state) do
    case authenticate(email, password) do
      {:ok, student} ->
        {:reply, :ok, %{state | student: student}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:logout, _from, state) do
    {:reply, :ok, %{state | student: nil}}
  end

  @impl true
  def handle_call({:set_session, student}, _from, state) do
    {:reply, :ok, %{state | student: student}}
  end

  def handle_call({:enroll, course_id}, _from, state) do
    if Map.has_key?(state.enrollments, course_id) do
      {:reply, {:error, "已选修该课程"}, state}
    else
      enrollment = %{enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second), completed: []}

      {:reply, {:ok, :enrolled},
       %{state | enrollments: Map.put(state.enrollments, course_id, enrollment)}}
    end
  end

  def handle_call({:enrolled?, course_id}, _from, state) do
    {:reply, Map.has_key?(state.enrollments, course_id), state}
  end

  def handle_call({:complete_lesson, course_id, lesson_id}, _from, state) do
    enrollments = state.enrollments

    case Map.get(enrollments, course_id) do
      nil ->
        {:reply, {:error, :not_enrolled}, state}

      enrollment ->
        completed =
          if lesson_id in enrollment.completed,
            do: enrollment.completed,
            else: [lesson_id | enrollment.completed]

        updated = %{enrollment | completed: completed}
        {:reply, :ok, %{state | enrollments: Map.put(enrollments, course_id, updated)}}
    end
  end

  def handle_call({:progress, course_id}, _from, state) do
    enrollment = Map.get(state.enrollments, course_id)
    lessons = Catalog.lessons(course_id)

    progress =
      case enrollment do
        nil ->
          %{completed: [], total: length(lessons), percent: 0}

        e ->
          %{
            completed: e.completed,
            total: length(lessons),
            percent: percent(e.completed, lessons)
          }
      end

    {:reply, progress, state}
  end

  def handle_call({:completed_lesson?, course_id, lesson_id}, _from, state) do
    completed =
      case Map.get(state.enrollments, course_id) do
        %{completed: list} -> lesson_id in list
        _ -> false
      end

    {:reply, completed, state}
  end

  def handle_call(:my_courses, _from, state) do
    courses =
      state.enrollments
      |> Map.keys()
      |> Enum.map(fn course_id ->
        course = Catalog.course(course_id)
        progress = progress_for(course_id, state)
        Map.merge(course, %{progress: progress})
      end)

    {:reply, courses, state}
  end

  def handle_call(:my_stats, _from, state) do
    lessons_done =
      state.enrollments
      |> Map.values()
      |> Enum.reduce(0, fn e, acc -> acc + length(e.completed) end)

    minutes = lessons_done * 20
    streak = if map_size(state.enrollments) > 0, do: 3, else: 0

    {:reply,
     %{
       courses: map_size(state.enrollments),
       lessons_done: lessons_done,
       study_minutes: minutes,
       streak: streak,
       mistakes: length(state.mistakes)
     }, state}
  end

  def handle_call(:mistakes, _from, state), do: {:reply, state.mistakes, state}

  def handle_call({:clear_mistake, id}, _from, state) do
    {:reply, :ok, %{state | mistakes: Enum.reject(state.mistakes, &(&1.id == id))}}
  end

  def handle_call(:notifications, _from, state), do: {:reply, state.notifications, state}

  def handle_call(:unread_count, _from, state) do
    count = Enum.count(state.notifications, &(not &1.read))
    {:reply, count, state}
  end

  def handle_call(:mark_notifications_read, _from, state) do
    notifications = Enum.map(state.notifications, &Map.put(&1, :read, true))
    {:reply, :ok, %{state | notifications: notifications}}
  end

  def handle_call(:chat_messages, _from, state), do: {:reply, state.chat_messages, state}

  def handle_call({:send_chat, text}, _from, state) do
    reply = Ai.qa_reply(text)
    now = stamp()
    messages = state.chat_messages ++ [msg(:user, text, now), msg(:assistant, reply, now)]
    {:reply, messages, %{state | chat_messages: messages}}
  end

  # ── 模拟患者 ────────────────────────────────────────────────────────────────

  def handle_call(:sp_sessions, _from, state) do
    sessions =
      Catalog.simulated_patients()
      |> Enum.map(fn patient ->
        session = Map.get(state.sp_sessions, patient.id, %{status: :not_started})
        Map.merge(patient, session)
      end)

    {:reply, sessions, state}
  end

  def handle_call({:sp_session, patient_id}, _from, state) do
    patient = Catalog.simulated_patient(patient_id)

    session =
      if patient do
        base =
          Map.get(state.sp_sessions, patient_id, %{
            status: :not_started,
            messages: [],
            shown: 0,
            dialectic: nil,
            grade: nil
          })

        Map.merge(patient, base)
      end

    {:reply, session, state}
  end

  def handle_call({:start_sp, patient_id}, _from, state) do
    patient = Catalog.simulated_patient(patient_id)

    session =
      Map.get(state.sp_sessions, patient_id) ||
        %{
          status: :in_progress,
          messages: [msg(:patient, patient.opening, stamp())],
          shown: 0,
          dialectic: nil,
          grade: nil
        }

    {:reply, Map.merge(patient, session),
     %{state | sp_sessions: Map.put(state.sp_sessions, patient_id, session)}}
  end

  def handle_call({:send_sp, patient_id, text}, _from, state) do
    session = Map.get(state.sp_sessions, patient_id)

    if session do
      {reply, shown} = Ai.sp_reply(patient_of(patient_id), session.shown, text)
      messages = session.messages ++ [msg(:student, text, stamp()), msg(:patient, reply, stamp())]
      updated = %{session | messages: messages, shown: shown}

      {:reply, Map.merge(patient_of(patient_id), updated),
       %{state | sp_sessions: Map.put(state.sp_sessions, patient_id, updated)}}
    else
      {:reply, nil, state}
    end
  end

  def handle_call({:submit_sp, patient_id, choice}, _from, state) do
    session = Map.get(state.sp_sessions, patient_id)

    if session do
      patient = patient_of(patient_id)
      grade = Ai.sp_grade(patient, choice)
      updated = %{session | status: :completed, dialectic: choice, grade: grade}

      {:reply, Map.merge(patient, updated),
       %{state | sp_sessions: Map.put(state.sp_sessions, patient_id, updated)}}
    else
      {:reply, nil, state}
    end
  end

  # ── MDT ─────────────────────────────────────────────────────────────────────

  def handle_call({:mdt_messages, room_id}, _from, state) do
    room = Catalog.mdt_room(room_id)
    extra = Map.get(state.mdt_messages, room_id, [])
    {:reply, %{room: room, messages: room.messages ++ extra}, state}
  end

  def handle_call({:send_mdt, room_id, text}, _from, state) do
    room = Catalog.mdt_room(room_id)
    extra = Map.get(state.mdt_messages, room_id, [])
    reply = Ai.mdt_reply(room, text)

    now = stamp()

    extra =
      extra ++
        [
          msg(:student, text, now),
          msg(:doctor, reply.text, now, %{speaker: reply.speaker, department: reply.role})
        ]

    {:reply, :ok, %{state | mdt_messages: Map.put(state.mdt_messages, room_id, extra)}}
  end

  # ── 测验 / 考试 ─────────────────────────────────────────────────────────────
  #
  # mode :quiz —— 单选当场判分，填空/问答只展示参考答案（不计入分数）；
  # mode :exam —— 整卷交卷后待人工评阅，不产生自动成绩。
  # 两种模式都要求所有题目已作答才允许交卷。

  def handle_call({:exam_attempt, exam_id}, _from, state) do
    {:reply, attempt_of(state, exam_id), state}
  end

  def handle_call({:exam_result, exam_id}, _from, state) do
    attempt = Map.get(state.exam_attempts, exam_id)

    result =
      if attempt && attempt.submitted do
        result_for(Catalog.exam(exam_id), attempt)
      end

    {:reply, result, state}
  end

  def handle_call({:save_answer, exam_id, question_id, value}, _from, state) do
    attempt = attempt_of(state, exam_id)
    updated = %{attempt | answers: Map.put(attempt.answers, question_id, value)}
    {:reply, :ok, %{state | exam_attempts: Map.put(state.exam_attempts, exam_id, updated)}}
  end

  def handle_call({:submit_exam, exam_id}, _from, state) do
    exam = Catalog.exam(exam_id)
    attempt = attempt_of(state, exam_id)

    case unanswered(exam, attempt) do
      [first | _] = missing ->
        {:reply, {:error, {:unanswered, length(missing), first}}, state}

      [] ->
        updated = grade(exam, attempt)
        state = %{state | exam_attempts: Map.put(state.exam_attempts, exam_id, updated)}

        state =
          if updated.graded?,
            do: %{state | mistakes: collect_mistakes(exam, attempt, state.mistakes)},
            else: state

        {:reply, result_for(exam, updated), state}
    end
  end

  # ── 资料下载 ────────────────────────────────────────────────────────────────

  def handle_call(:downloads, _from, state) do
    resources =
      Enum.map(
        Catalog.resources(),
        &Map.put(&1, :downloaded, Map.get(state.downloads, &1.id, false))
      )

    {:reply, resources, state}
  end

  def handle_call({:toggle_download, id}, _from, state) do
    downloads = Map.update(state.downloads, id, true, &(not &1))
    {:reply, :ok, %{state | downloads: downloads}}
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp attempt_of(state, exam_id),
    do:
      Map.get(state.exam_attempts, exam_id, %{
        answers: %{},
        submitted: false,
        score: nil,
        pass?: nil,
        graded?: nil,
        correct: nil,
        choice_total: nil,
        submitted_at: nil
      })

  # 未作答题目的**绝对**下标（题号 - 1），过滤前先带上下标。
  defp unanswered(exam, attempt) do
    exam.questions
    |> Enum.with_index()
    |> Enum.reject(fn {question, _idx} -> answered?(question, attempt) end)
    |> Enum.map(fn {_question, idx} -> idx end)
  end

  defp answered?(question, attempt),
    do: Questions.answered?(question, Map.get(attempt.answers, question.id))

  defp grade(exam, attempt) do
    choices = Enum.filter(exam.questions, &(Questions.type(&1) == :single))
    correct = Enum.count(choices, fn q -> Map.get(attempt.answers, q.id) == q.answer end)
    choice_total = length(choices)

    case exam.mode do
      :exam ->
        %{attempt | submitted: true, graded?: false, submitted_at: stamp()}

      _ ->
        score = if choice_total == 0, do: 0, else: round(correct / choice_total * 100)

        %{
          attempt
          | submitted: true,
            graded?: true,
            score: score,
            pass?: score >= exam.pass_score,
            correct: correct,
            choice_total: choice_total,
            submitted_at: stamp()
        }
    end
  end

  defp result_for(exam, attempt) do
    %{
      mode: exam.mode,
      graded?: attempt.graded? == true,
      score: attempt.score,
      pass?: attempt.pass?,
      correct: attempt.correct,
      choice_total: attempt.choice_total,
      total: length(exam.questions),
      attempt: attempt
    }
  end

  # 错题自动入错题本 —— 只收测验里判错的单选题。
  defp collect_mistakes(exam, attempt, mistakes) do
    Enum.reduce(exam.questions, mistakes, fn question, acc ->
      if wrong_choice?(question, attempt),
        do: push_mistake(acc, mistake_of(question, exam, attempt)),
        else: acc
    end)
  end

  defp wrong_choice?(question, attempt) do
    Questions.type(question) == :single and
      Map.get(attempt.answers, question.id) != question.answer
  end

  defp push_mistake(acc, mistake) do
    if Enum.any?(acc, &(&1.question == mistake.question)), do: acc, else: acc ++ [mistake]
  end

  defp mistake_of(question, exam, attempt) do
    %{
      id: System.unique_integer([:positive]),
      question: question.text,
      options: question.options,
      my_answer: Map.get(attempt.answers, question.id),
      correct_answer: question.answer,
      explanation: question.explanation,
      source: exam.title
    }
  end

  defp authenticate(email, password) do
    demo = Catalog.demo_student()

    cond do
      String.trim(email) == "" or password == "" ->
        {:error, "请输入账号和密码"}

      String.downcase(String.trim(email)) == demo.email and password == "123456" ->
        {:ok, demo}

      true ->
        {:error, "账号或密码错误"}
    end
  end

  defp patient_of(id), do: Catalog.simulated_patient(id)

  defp percent(completed, lessons) do
    if lessons == [], do: 0, else: round(length(completed) / length(lessons) * 100)
  end

  defp progress_for(course_id, state) do
    enrollment = Map.get(state.enrollments, course_id)
    lessons = Catalog.lessons(course_id)

    case enrollment do
      nil ->
        %{completed: [], total: length(lessons), percent: 0}

      e ->
        %{completed: e.completed, total: length(lessons), percent: percent(e.completed, lessons)}
    end
  end

  defp msg(role, text, time, extra \\ %{}) do
    Map.merge(%{role: role, text: text, time: time}, extra)
  end

  defp stamp do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    :io_lib.format("~2..0B:~2..0B", [now.hour, now.minute]) |> IO.iodata_to_binary()
  end
end
