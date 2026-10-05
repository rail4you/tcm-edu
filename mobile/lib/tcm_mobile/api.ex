defmodule TcmMobile.Api do
  @moduledoc """
  学员端数据访问层 —— 界面只依赖这一个模块。

  - `source: :local`（默认）：数据来自 `TcmMobile.Store` 与 `TcmMobile.Data.Catalog`，
    完全离线可用。
  - `source: :remote`：通过 Req 请求后端 JSON API（后端补 API 后启用；
    地址在 `config/runtime.exs` 或环境变量 `TCM_API_URL` 配置）。

  两层返回相同的数据形状，界面层无感知。
  """

  alias TcmMobile.Data.Catalog
  alias TcmMobile.Store

  # ── 数据源选择 ──────────────────────────────────────────────────────────────

  @spec source() :: :local | :remote
  def source do
    Application.get_env(:tcm_mobile, :api_source, :local)
  end

  defp local?, do: source() == :local

  defp call(fun, remote_fun) do
    if local?(), do: fun.(), else: remote_fun.()
  end

  # ── 认证 ────────────────────────────────────────────────────────────────────

  def student, do: call(&Store.student/0, fn -> remote_get("/me") end)
  def logged_in?, do: student() != nil

  def login(email, password) do
    if local?() do
      Store.login(email, password)
    else
      with {:ok, body} <- remote_post("/auth/login", %{email: email, password: password}) do
        {:ok, body["user"]}
      end
    end
  end

  def logout, do: call(&Store.logout/0, fn -> :ok end)

  # ── 首页 ────────────────────────────────────────────────────────────────────

  def home_stats do
    stats = Store.my_stats()
    %{teachers: Catalog.teachers(), categories: Catalog.categories(), stats: stats}
  end

  def list_categories, do: Catalog.categories()
  def popular_courses, do: Catalog.popular_courses()
  def list_teachers, do: Catalog.teachers()

  # ── 课程 ────────────────────────────────────────────────────────────────────

  def list_courses(category \\ nil) do
    case category do
      nil -> Catalog.courses()
      cat -> Catalog.courses_by_category(cat)
    end
  end

  def search_courses(query), do: Catalog.search_courses(query)

  def get_course(id) do
    course = Catalog.course(id)

    if course do
      Map.merge(course, %{
        lessons: Catalog.lessons(id),
        teacher: Catalog.teacher(course.teacher_id)
      })
    end
  end

  def enroll(course_id), do: Store.enroll(course_id)
  def enrolled?(course_id), do: Store.enrolled?(course_id)
  def complete_lesson(course_id, lesson_id), do: Store.complete_lesson(course_id, lesson_id)
  def progress(course_id), do: Store.progress(course_id)
  def completed_lesson?(course_id, lesson_id), do: Store.completed_lesson?(course_id, lesson_id)
  def my_courses, do: Store.my_courses()
  def my_stats, do: Store.my_stats()

  def lesson(course_id, lesson_id) do
    Catalog.lesson(course_id, lesson_id)
  end

  def lesson_content(lesson_id), do: Catalog.lesson_content(lesson_id)
  def lesson_quiz(lesson_id), do: Catalog.lesson_quiz(lesson_id)

  # ── 错题本 ──────────────────────────────────────────────────────────────────

  def mistakes, do: Store.mistakes()
  def clear_mistake(id), do: Store.clear_mistake(id)

  # ── 测验 ────────────────────────────────────────────────────────────────────

  def list_exams, do: Catalog.exams()
  def get_exam(id), do: Catalog.exam(id)
  def exam_attempt(exam_id), do: Store.exam_attempt(exam_id)
  def save_answer(exam_id, qid, index), do: Store.save_answer(exam_id, qid, index)
  def submit_exam(exam_id), do: Store.submit_exam(exam_id)

  # ── 学习问答 ────────────────────────────────────────────────────────────────

  def chat_messages, do: Store.chat_messages()
  def send_chat(text), do: Store.send_chat(text)

  # ── 模拟患者 ────────────────────────────────────────────────────────────────

  def list_sp_patients, do: Store.sp_sessions()
  def sp_session(patient_id), do: Store.sp_session(patient_id)
  def start_sp(patient_id), do: Store.start_sp(patient_id)
  def send_sp(patient_id, text), do: Store.send_sp(patient_id, text)
  def submit_sp(patient_id, choice), do: Store.submit_sp(patient_id, choice)

  # ── MDT ─────────────────────────────────────────────────────────────────────

  def list_mdt_rooms, do: Catalog.mdt_rooms()
  def mdt_room(room_id), do: Store.mdt_messages(room_id)
  def send_mdt(room_id, text), do: Store.send_mdt(room_id, text)

  # ── 通知 / 资料 ─────────────────────────────────────────────────────────────

  def notifications, do: Store.notifications()
  def unread_count, do: Store.unread_count()
  def mark_notifications_read, do: Store.mark_notifications_read()
  def list_downloads, do: Store.downloads()
  def toggle_download(id), do: Store.toggle_download(id)

  # ── 远程（预留）─────────────────────────────────────────────────────────────

  defp remote_get(path) do
    case Req.get(base_url() <> path) do
      {:ok, resp} -> {:ok, resp.body}
      error -> error
    end
  end

  defp remote_post(path, body) do
    case Req.post(base_url() <> path, json: body) do
      {:ok, resp} -> {:ok, resp.body}
      error -> error
    end
  end

  defp base_url, do: Application.get_env(:tcm_mobile, :api_url, "http://localhost:4000/api")
end
