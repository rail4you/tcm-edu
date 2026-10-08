defmodule TcmMobile.Api do
  @moduledoc """
  学员端数据访问层 —— 界面只依赖这一个模块。

  - `source: :remote`（默认）：认证走本地 Phoenix JSON API
    （`POST /api/auth/user/password/sign_in`、`GET /api/auth/me`），业务数据走后端
    `AshJsonApi` 从 Ash DSL 自动生成的 `/api/student/*`（课程目录、选课、课时进度、
    首页统计、通知、考试记录）。token 持久化在 `Mob.State`，启动时自动恢复会话。
  - `source: :local`：全部来自 `TcmMobile.Store` 与 `TcmMobile.Data.Catalog`，
    完全离线可用。

  远程请求失败（未登录 / 断网 / 服务未启动 / 404）一律**静默回落本地数据**，保证
  离线仍能进入界面；读请求带 15s 内存缓存，避免同一屏反复取数、离线时长时间阻塞。
  写请求只对后端生成的 UUID 资源发起，本地目录里的假 id（`c1`…）仍然只写本地 Store。

  地址与租户在 `config/config.exs`（`api_url` / `api_org_slug`）配置，
  也可用环境变量 `TCM_API_SOURCE` / `TCM_API_URL` / `TCM_ORG_SLUG` 覆盖。
  """

  alias TcmMobile.Data.Catalog
  alias TcmMobile.Store

  @token_key :tcm_api_token
  @timeout 8_000
  @restore_timeout 2_500
  @biz_timeout 3_000
  @jsonapi "application/vnd.api+json"
  @cache_ttl 15_000
  @cache_keys [:overview, :enrollments, :notifications, :catalog, :exam_records]
  @uuid ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  # ── 数据源选择 ──────────────────────────────────────────────────────────────

  @spec source() :: :local | :remote
  def source do
    case System.get_env("TCM_API_SOURCE") ||
           Application.get_env(:tcm_mobile, :api_source, :local) do
      v when v in ["remote", :remote] -> :remote
      _ -> :local
    end
  end

  def local?, do: source() == :local

  # ── 认证 ────────────────────────────────────────────────────────────────────

  def student, do: Store.student()
  def logged_in?, do: Store.logged_in?()

  def login(email, password) do
    if local?() do
      Store.login(email, password)
    else
      remote_login(email, password)
    end
  end

  def logout do
    if local?() do
      Store.logout()
    else
      _ = request(:post, "/auth/sign_out", %{})
      Mob.State.delete(@token_key)
      clear_cache()
      Store.logout()
      :ok
    end
  end

  @doc """
  远程模式下用持久化的 token 恢复会话。应用启动时调用；任何失败都静默降级
  （token 失效才清掉），保证离线仍能进入界面。
  """
  def restore_session do
    cond do
      local?() ->
        :ok

      is_nil(Mob.State.get(@token_key)) ->
        :ok

      true ->
        case request(:get, "/auth/me", nil, @restore_timeout) do
          {:ok, %{"data" => data}} ->
            Store.set_session(to_student(data))
            :ok

          {:error, :unauthorized} ->
            Mob.State.delete(@token_key)
            clear_cache()

          _ ->
            :ok
        end
    end
  end

  # ── 首页 ────────────────────────────────────────────────────────────────────

  def home_stats do
    %{teachers: Catalog.teachers(), categories: list_categories(), stats: my_stats()}
  end

  def my_stats do
    local = Store.my_stats()

    case jsonapi_get("/student/enrollments/overview", :overview) do
      {:ok, %{"enrolled_courses" => _} = ov} ->
        %{
          courses: ov["enrolled_courses"] || 0,
          lessons_done: ov["completed_lessons"] || 0,
          study_minutes: div(ov["study_seconds"] || 0, 60),
          streak: ov["streak_days"] || 0,
          mistakes: local.mistakes
        }

      _ ->
        local
    end
  end

  def list_categories do
    case remote_catalog() do
      {:ok, courses} ->
        courses
        |> Enum.map(& &1.category_ref)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)
        |> Enum.sort_by(& &1.sort_order)
        |> Enum.map(&%{id: &1.id, name: &1.name, icon: &1.icon})

      _ ->
        Catalog.categories()
    end
  end

  def popular_courses do
    case remote_catalog() do
      {:ok, courses} -> Enum.take(courses, 10)
      _ -> Catalog.popular_courses()
    end
  end

  # ── 课程目录 ────────────────────────────────────────────────────────────────

  def list_courses(category \\ nil) do
    case remote_catalog() do
      {:ok, courses} ->
        case category do
          nil -> courses
          cat -> Enum.filter(courses, &(&1.category_id == cat))
        end

      _ ->
        case category do
          nil -> Catalog.courses()
          cat -> Catalog.courses_by_category(cat)
        end
    end
  end

  def search_courses(query) do
    case remote_catalog() do
      {:ok, courses} -> Enum.filter(courses, &matches?(&1, query))
      _ -> Catalog.search_courses(query)
    end
  end

  def get_course(id) do
    case remote_course(id) do
      {:ok, course} ->
        course

      _ ->
        cached_list_course(id) || local_course(id) || empty_course(id)
    end
  end

  def lesson(course_id, lesson_id) do
    course = get_course(course_id)
    course && Enum.find(course.lessons, &(&1.id == lesson_id))
  end

  def lesson_content(lesson_id, course_id \\ nil) do
    with true <- remote_session?(),
         course when not is_nil(course) <- get_course(course_id),
         lesson when not is_nil(lesson) <- Enum.find(course.lessons, &(&1.id == lesson_id)) do
      remote_lesson_content(lesson)
    else
      _ -> Catalog.lesson_content(lesson_id)
    end
  end

  def lesson_quiz(lesson_id), do: Catalog.lesson_quiz(lesson_id)

  # ── 选课 / 进度 ─────────────────────────────────────────────────────────────

  def enroll(course_id) do
    if uuid?(course_id) do
      payload = %{
        "data" => %{"type" => "enrollment", "attributes" => %{"course_id" => course_id}}
      }

      case jsonapi_post("/student/enrollments", payload) do
        {:ok, _} ->
          invalidate(:enrollments)
          {:ok, :enrolled}

        {:error, :unauthorized} ->
          {:error, "登录已过期，请重新登录"}

        {:error, _} ->
          {:error, "选课失败，请稍后重试"}
      end
    else
      Store.enroll(course_id)
    end
  end

  # 本地目录 id（c1…c10）不是后端记录：不发请求，直接查本地 store
  def enrolled?(course_id) do
    if uuid?(course_id) do
      case remote_my_courses() do
        {:ok, courses} ->
          Enum.any?(courses, &(&1.id == course_id)) or Store.enrolled?(course_id)

        _ ->
          Store.enrolled?(course_id)
      end
    else
      Store.enrolled?(course_id)
    end
  end

  def complete_lesson(course_id, lesson_id) do
    case remote_course_progress_ref(course_id) do
      {:ok, enrollment_id} ->
        _ = post_progress(enrollment_id, lesson_id)
        :ok

      _ ->
        Store.complete_lesson(course_id, lesson_id)
    end
  end

  def progress(course_id) do
    case find_remote_course(course_id) do
      %{progress: progress} -> progress
      nil -> Store.progress(course_id)
    end
  end

  def completed_lesson?(course_id, lesson_id) do
    case find_remote_course(course_id) do
      %{progress: %{completed: completed}} -> lesson_id in completed
      nil -> Store.completed_lesson?(course_id, lesson_id)
    end
  end

  def my_courses do
    case remote_my_courses() do
      {:ok, remote} ->
        remote_ids = MapSet.new(remote, & &1.id)
        remote ++ Enum.reject(Store.my_courses(), &MapSet.member?(remote_ids, &1.id))

      _ ->
        Store.my_courses()
    end
  end

  # ── 错题本 ──────────────────────────────────────────────────────────────────

  def mistakes, do: Store.mistakes()
  def clear_mistake(id), do: Store.clear_mistake(id)

  # ── 测验 / 考试记录 ─────────────────────────────────────────────────────────

  def list_exams, do: Catalog.exams()
  def get_exam(id), do: Catalog.exam(id)
  def exam_attempt(exam_id), do: Store.exam_attempt(exam_id)
  def exam_result(exam_id), do: Store.exam_result(exam_id)
  def save_answer(exam_id, qid, index), do: Store.save_answer(exam_id, qid, index)
  def submit_exam(exam_id), do: Store.submit_exam(exam_id)

  @doc "我的考试记录（后端 `ExamAssignment`，远程失败时返回空列表）。"
  def my_exam_records do
    case jsonapi_get("/student/exam-assignments?include=exam", :exam_records) do
      {:ok, %{"data" => data} = body} when is_list(data) ->
        exams = Map.new(exam_resources(body), &{&1["id"], &1})
        Enum.map(data, &exam_record(&1, exams))

      _ ->
        []
    end
  end

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

  def notifications do
    case jsonapi_get("/student/notifications", :notifications) do
      {:ok, %{"data" => data}} when is_list(data) -> Enum.map(data, &notification/1)
      _ -> Store.notifications()
    end
  end

  def unread_count do
    notifications()
    |> Enum.count(&(not &1.read))
  end

  def mark_notifications_read do
    _ = Store.mark_notifications_read()

    if remote_session?() do
      case jsonapi_post("/student/notifications/mark_all_read", %{}) do
        {:ok, _} -> invalidate(:notifications)
        _ -> :ok
      end
    end

    :ok
  end

  def list_downloads, do: Store.downloads()
  def toggle_download(id), do: Store.toggle_download(id)

  @doc """
  把 PDF 地址包成后端的同源转发地址（`/pdfjs/doc?u=…`）。

  设备侧的 BEAM 没有可用的 `:crypto`，任何 `https://` 直连都会死在 TLS
  握手上；后端转发端点跑在宿主机上、由它去取上游，手机侧只需要走
  `http://` 回环。同时上游主机由后端白名单限制，这里也就顺带复用了。
  """
  @spec proxy_pdf_url(String.t()) :: String.t()
  def proxy_pdf_url(url) do
    web_base_url() <> "/pdfjs/doc?u=" <> URI.encode(url, &URI.char_unreserved?/1)
  end

  @doc """
  后端站点的 origin（去掉 `/api` 路径），用于加载同源静态资源——
  自托管的 pdf.js viewer（`/pdfjs/web/viewer.html`）和它的 PDF 同源
  转发端点（`/pdfjs/doc?u=…`）都挂在这个 origin 下。
  """
  @spec web_base_url() :: String.t()
  def web_base_url do
    case URI.new(base_url()) do
      {:ok, %URI{scheme: scheme, host: host} = uri} when is_binary(scheme) and is_binary(host) ->
        uri
        |> Map.merge(%{path: "", query: nil, fragment: nil})
        |> URI.to_string()

      _ ->
        "http://127.0.0.1:4011"
    end
  end

  # ── 远程认证 ────────────────────────────────────────────────────────────────

  defp remote_login(email, password) do
    payload = %{"user" => %{"email" => email, "password" => password}}

    payload =
      case org_slug() do
        nil -> payload
        slug -> Map.put(payload, "organization_slug", slug)
      end

    with {:ok, %{"authentication" => %{"bearer" => bearer}}} <-
           request(:post, "/auth/user/password/sign_in", payload),
         :ok <- Mob.State.put(@token_key, bearer),
         {:ok, %{"data" => data}} <- request(:get, "/auth/me") do
      clear_cache()
      Store.set_session(to_student(data))
      :ok
    else
      {:error, reason} -> {:error, friendly(reason)}
      _ -> {:error, "账号或密码错误"}
    end
  end

  # ── AshJsonApi 客户端 ───────────────────────────────────────────────────────

  defp remote_session?, do: not local?() and not is_nil(Mob.State.get(@token_key))

  defp uuid?(id), do: is_binary(id) and Regex.match?(@uuid, id)

  defp jsonapi_get(path, key) do
    if remote_session?() do
      cached(key, fn -> jsonapi_request(:get, path, nil) end)
    else
      {:error, :no_session}
    end
  end

  defp jsonapi_post(path, payload) do
    if remote_session?() do
      jsonapi_request(:post, path, payload)
    else
      {:error, :no_session}
    end
  end

  # JSON:API 必须显式带上 media type：Accept 缺省拿不到 vnd.api+json，
  # 而 POST 用 application/json 会被后端判 415。
  defp jsonapi_request(method, path, body) do
    headers =
      auth_headers() ++
        [{"accept", @jsonapi}] ++
        if(method == :post, do: [{"content-type", @jsonapi}], else: [])

    opts = [headers: headers, receive_timeout: @biz_timeout, retry: false] ++ http_plug()

    resp =
      case method do
        :get -> Req.get(base_url() <> path, opts)
        :post -> Req.post(base_url() <> path, opts ++ [body: Jason.encode!(body || %{})])
      end

    decode(resp)
  end

  # 测试注入点：配置了 `:api_req_plug` 时把请求交给 Req.Test 的桩，生产恒为 nil。
  defp http_plug do
    case Application.get_env(:tcm_mobile, :api_req_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end

  # ── 读缓存：15s TTL，失败时回退上一次成功结果 ───────────────────────────────

  defp cached(key, fetch) do
    now = System.monotonic_time(:millisecond)
    cache_key = {__MODULE__, :cache, key}

    case :persistent_term.get(cache_key, nil) do
      {ts, value} when now - ts < @cache_ttl -> {:ok, value}
      stale -> refresh(cache_key, now, stale, fetch)
    end
  end

  # 缓存过期（或全无）时取数；取不到就退回上一次成功的值，保证离线不白屏。
  defp refresh(cache_key, now, stale, fetch) do
    case fetch.() do
      {:ok, value} ->
        :persistent_term.put(cache_key, {now, value})
        {:ok, value}

      {:error, _} = error ->
        case stale do
          {_ts, previous} -> {:ok, previous}
          nil -> error
        end
    end
  end

  defp invalidate(key), do: :persistent_term.erase({__MODULE__, :cache, key})

  @doc false
  def clear_cache do
    Enum.each(@cache_keys, &invalidate/1)
    :ok
  end

  # ── 业务读取 ────────────────────────────────────────────────────────────────

  defp remote_catalog do
    case jsonapi_get("/student/courses?include=category,chapters.lessons", :catalog) do
      {:ok, %{"data" => data} = body} when is_list(data) ->
        {:ok, Enum.map(data, &course_from_json(&1, body))}

      other ->
        other
    end
  end

  defp remote_my_courses do
    jsonapi_get(
      "/student/enrollments?include=course.chapters.lessons,progress_records",
      :enrollments
    )
    |> case do
      {:ok, %{"data" => data} = body} when is_list(data) ->
        {:ok, enrollments_to_courses(body)}

      other ->
        other
    end
  end

  defp remote_course(id) do
    with true <- uuid?(id),
         {:ok, %{"data" => %{"type" => "course"} = resource} = body} <-
           jsonapi_get("/student/courses/#{id}?include=category,chapters.lessons", {:course, id}) do
      {:ok, course_from_json(resource, body)}
    else
      _ -> {:error, :not_found}
    end
  end

  # 本地 id 直接返回 nil，调用方（progress/1、completed_lesson?/2）回落到 Store
  defp find_remote_course(course_id) do
    with true <- uuid?(course_id),
         {:ok, courses} <- remote_my_courses() do
      Enum.find(courses, &(&1.id == course_id))
    else
      _ -> nil
    end
  end

  # 详情页可能点进一个只出现在列表缓存里的课程（离线 / 404 时兜底）
  defp cached_list_course(course_id) do
    (cached_catalog_courses() ++ cached_enrollment_courses())
    |> Enum.find(&(&1.id == course_id))
  end

  defp cached_catalog_courses do
    case :persistent_term.get({__MODULE__, :cache, :catalog}, nil) do
      {_ts, %{"data" => data} = body} when is_list(data) ->
        Enum.map(data, &course_from_json(&1, body))

      _ ->
        []
    end
  end

  defp cached_enrollment_courses do
    case :persistent_term.get({__MODULE__, :cache, :enrollments}, nil) do
      {_ts, %{"data" => data} = body} when is_list(data) ->
        enrollments_to_courses(body)

      _ ->
        []
    end
  end

  defp remote_course_progress_ref(course_id) do
    with true <- uuid?(course_id),
         %{enrollment_id: enrollment_id} <- find_remote_course(course_id) do
      {:ok, enrollment_id}
    else
      _ -> {:error, :not_remote}
    end
  end

  defp post_progress(enrollment_id, lesson_id) do
    payload = %{
      "data" => %{
        "type" => "progress",
        "attributes" => %{
          "enrollment_id" => enrollment_id,
          "lesson_id" => lesson_id,
          "status" => "completed",
          "progress_pct" => 100,
          "last_position_seconds" => 0
        }
      }
    }

    result = jsonapi_post("/student/progress", payload)
    invalidate(:enrollments)
    result
  end

  # ── JSON:API 解码 ───────────────────────────────────────────────────────────

  defp enrollments_to_courses(body) do
    ctx = payload_index(body)

    body["data"]
    |> Enum.flat_map(fn enrollment ->
      course_id = enrollment["attributes"]["course_id"]
      course = Map.get(ctx.courses, course_id)

      if course do
        [course_from_json(course, ctx.payload, enrollment_progress(enrollment, ctx))]
      else
        []
      end
    end)
  end

  defp payload_index(body) do
    included = body["included"] || []
    payload = %{"data" => body["data"], "included" => included}

    %{
      payload: payload,
      courses: Map.new(inc_of(included, "course"), &{&1["id"], &1}),
      chapters: inc_of(included, "chapter"),
      lessons: inc_of(included, "lesson"),
      categories: Map.new(inc_of(included, "course_category"), &{&1["id"], &1}),
      progress: inc_of(included, "progress")
    }
  end

  defp enrollment_progress(enrollment, ctx) do
    ids =
      enrollment
      |> get_in(["relationships", "progress_records", "data"])
      |> List.wrap()
      |> Enum.map(& &1["id"])
      |> MapSet.new()

    records = Enum.filter(ctx.progress, &MapSet.member?(ids, &1["id"]))
    course_id = enrollment["attributes"]["course_id"]
    lessons = course_lessons(course_id, ctx)

    completed =
      records
      |> Enum.filter(&(&1["attributes"]["status"] == "completed"))
      |> Enum.map(& &1["attributes"]["lesson_id"])

    total = length(lessons)

    %{
      completed: completed,
      total: total,
      percent: if(total == 0, do: 0, else: round(length(completed) / total * 100))
    }
  end

  defp course_from_json(resource, payload, progress \\ nil) do
    attrs = resource["attributes"]
    ctx = payload_index(payload)
    category = Map.get(ctx.categories, attrs["category_id"])
    lessons = course_lessons(resource["id"], ctx)

    %{
      id: resource["id"],
      title: attrs["title"],
      subtitle: attrs["subtitle"] || "",
      description: attrs["description"] || "",
      level: level_atom(attrs["level"]),
      tags: attrs["tags"] || [],
      price_cents: attrs["price_cents"] || 0,
      status: attrs["status"],
      category_id: attrs["category_id"],
      category: category && (category["attributes"]["slug"] || category["attributes"]["name"]),
      student_count: 0,
      lesson_count: length(lessons),
      lessons: lessons,
      teacher: %{name: "授课教师", title: "", specialty: ""},
      category_ref: category_ref(category),
      progress: progress || %{completed: [], total: length(lessons), percent: 0},
      enrollment_id: nil
    }
    |> put_enrollment_id(payload, resource["id"])
  end

  defp category_ref(nil), do: nil

  defp category_ref(resource) do
    attrs = resource["attributes"]

    %{
      id: resource["id"],
      name: attrs["name"],
      slug: attrs["slug"],
      icon: attrs["icon"],
      sort_order: attrs["sort_order"] || 0
    }
  end

  defp put_enrollment_id(course, payload, course_id) do
    data = if is_list(payload["data"]), do: payload["data"], else: []

    enrollment =
      Enum.find(data, fn e -> e["attributes"]["course_id"] == course_id end)

    case enrollment do
      nil -> course
      found -> %{course | enrollment_id: found["id"]}
    end
  end

  defp course_lessons(course_id, ctx) do
    chapters =
      ctx.chapters
      |> Enum.filter(&(&1["attributes"]["course_id"] == course_id))
      |> Enum.sort_by(&(&1["attributes"]["sort_order"] || 0))

    chapters
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {chapter, chapter_no} ->
      ctx.lessons
      |> Enum.filter(&(&1["attributes"]["chapter_id"] == chapter["id"]))
      |> Enum.sort_by(&(&1["attributes"]["sort_order"] || 0))
      |> Enum.with_index(1)
      |> Enum.map(fn {lesson, no} -> lesson_from_json(lesson, course_id, chapter_no, no) end)
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {lesson, index} -> %{lesson | no: index} end)
  end

  defp lesson_from_json(resource, course_id, chapter_no, no) do
    attrs = resource["attributes"]

    %{
      id: resource["id"],
      course_id: course_id,
      chapter_no: chapter_no,
      no: no,
      title: attrs["title"],
      kind: kind_atom(attrs["content_type"]),
      duration_min: div(attrs["duration_seconds"] || 0, 60),
      content: content_paragraphs(attrs["content_text"])
    }
  end

  defp content_paragraphs(nil), do: nil

  defp content_paragraphs(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> case do
      [] -> nil
      paragraphs -> paragraphs
    end
  end

  defp notification(resource) do
    attrs = resource["attributes"]

    %{
      id: resource["id"],
      title: attrs["title"] || "",
      body: attrs["body"] || "",
      time: format_time(attrs["inserted_at"]),
      read: not is_nil(attrs["read_at"])
    }
  end

  defp exam_record(resource, exams) do
    attrs = resource["attributes"]
    exam = Map.get(exams, attrs["exam_id"])
    exam_attrs = exam && exam["attributes"]

    %{
      id: resource["id"],
      exam_id: attrs["exam_id"],
      exam_name: (exam_attrs && exam_attrs["name"]) || "测验",
      status: attrs["status"],
      score: parse_score(attrs["total_score"]),
      assigned_at: attrs["assigned_at"],
      graded_at: attrs["graded_at"]
    }
  end

  defp exam_resources(body), do: inc_of(body["included"] || [], "exam")

  defp inc_of(included, type), do: Enum.filter(included, &(&1["type"] == type))

  defp level_atom("intermediate"), do: :intermediate
  defp level_atom("advanced"), do: :advanced
  defp level_atom(_), do: :beginner

  defp kind_atom("video"), do: :video
  defp kind_atom(_), do: :text

  defp parse_score(nil), do: nil
  defp parse_score(value) when is_number(value), do: value * 1.0

  defp parse_score(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp format_time(nil), do: ""

  defp format_time(iso) when is_binary(iso) do
    case String.split(iso, "T") do
      [date, rest] -> date <> " " <> String.slice(rest, 0, 5)
      _ -> String.slice(iso, 0, 10)
    end
  end

  defp matches?(course, query) do
    q = String.downcase(String.trim(query))

    q == "" or String.contains?(String.downcase(course.title), q) or
      Enum.any?(course.tags, &String.contains?(String.downcase(&1), q))
  end

  defp local_course(id) do
    course = Catalog.course(id)

    if course do
      Map.merge(course, %{
        lessons: Catalog.lessons(id),
        teacher: Catalog.teacher(course.teacher_id) || %{name: "授课教师", title: "", specialty: ""}
      })
    end
  end

  # 一个既不在本地目录、又拉不到详情的远端 id：给一张空卡片，避免详情页崩溃
  defp empty_course(id) do
    unless uuid?(id), do: throw(:not_applicable)

    %{
      id: id,
      title: "课程暂不可用",
      subtitle: "",
      description: "离线状态下暂时无法加载该课程详情，恢复网络后重试。",
      level: :beginner,
      tags: [],
      price_cents: 0,
      category_id: nil,
      category: nil,
      student_count: 0,
      lesson_count: 0,
      lessons: [],
      teacher: %{name: "授课教师", title: "", specialty: ""},
      progress: %{completed: [], total: 0, percent: 0},
      enrollment_id: nil
    }
  catch
    :not_applicable -> nil
  end

  defp remote_lesson_content(lesson) do
    lesson[:content] || ["（本课时暂无正文内容）"]
  end

  # ── 通用 HTTP ───────────────────────────────────────────────────────────────

  defp request(method, path, body \\ nil, timeout \\ @timeout) do
    opts = [headers: auth_headers(), receive_timeout: timeout, retry: false] ++ http_plug()

    resp =
      case method do
        :get -> Req.get(base_url() <> path, opts)
        :post -> Req.post(base_url() <> path, opts ++ [json: body || %{}])
      end

    decode(resp)
  end

  defp decode({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp decode({:ok, %Req.Response{status: status}}) when status in [401, 403],
    do: {:error, :unauthorized}

  defp decode({:ok, %Req.Response{status: status}}) when status >= 500, do: {:error, :server}
  defp decode({:ok, %Req.Response{}}), do: {:error, :bad_request}
  defp decode({:error, _}), do: {:error, :offline}

  defp friendly(:offline), do: "连不上本地服务（确认 mix phx.server 已启动）"
  defp friendly(:unauthorized), do: "账号或密码错误"
  defp friendly(:server), do: "服务端错误，请稍后再试"
  defp friendly(_), do: "请求失败，请重试"

  defp to_student(%{"id" => id, "email" => email} = data) do
    name = data["name"] || email

    %{
      id: id,
      name: name,
      email: email,
      tenant: data["tenant"],
      avatar: data["avatar"] || String.first(name) || "学"
    }
  end

  defp auth_headers do
    case Mob.State.get(@token_key) do
      nil -> []
      token -> [{"authorization", "Bearer " <> token}]
    end
  end

  defp base_url do
    System.get_env("TCM_API_URL") ||
      Application.get_env(:tcm_mobile, :api_url, "http://127.0.0.1:4011/api")
  end

  defp org_slug do
    System.get_env("TCM_ORG_SLUG") || Application.get_env(:tcm_mobile, :api_org_slug)
  end
end
