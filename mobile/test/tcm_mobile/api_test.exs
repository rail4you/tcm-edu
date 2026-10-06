defmodule TcmMobile.ApiTest do
  @moduledoc """
  `TcmMobile.Api` 的远程（JSON:API）路径。

  后端真实接口的契约由
  `test/tcm_edu_web/json_api/student_json_api_test.exs` 覆盖；这里只测移动端
  这一侧：请求头/请求体、JSON:API 解码、15s 缓存、以及"远程失败静默回落
  本地"这条离线保证。HTTP 用 `Req.Test` 桩掉（`config.exs` 的
  `:api_req_plug` 注入点），因此不碰网络。

  测试固定 `async: false`：`Store` 是全局命名单例，`:persistent_term` 缓存与
  `Mob.State` 的 token 都是进程间共享的。
  """

  use ExUnit.Case, async: false

  alias TcmMobile.Api
  alias TcmMobile.Data.Catalog

  @jsonapi "application/vnd.api+json"
  @course_id "0a7009bb-43af-4e97-92e4-3cabd8ffa575"
  @category_id "630d6387-6689-46f2-9e61-8ba1088f5724"
  @chapter_id "4567117b-61cd-4db7-b770-e9e5caf6beda"
  @lesson_a "81960539-2c64-4472-82b0-bb77e534beaf"
  @lesson_b "b32dfa6e-8270-4c23-b1c5-8aec134ba38d"
  @enrollment_id "825bf2f5-2ab8-4c88-95bb-f0cca271d407"
  @other_course_id "11111111-2222-3333-4444-555555555555"

  setup do
    Req.Test.verify_on_exit!()

    prev_source = Application.get_env(:tcm_mobile, :api_source)
    prev_env = System.get_env("TCM_API_SOURCE")

    System.delete_env("TCM_API_SOURCE")
    Application.put_env(:tcm_mobile, :api_source, :remote)
    Application.put_env(:tcm_mobile, :api_req_plug, {Req.Test, :tcm_api})

    TcmMobile.Store.reset()
    Mob.State.put(:tcm_api_token, "test-token")
    Api.clear_cache()

    on_exit(fn ->
      Application.put_env(:tcm_mobile, :api_source, prev_source || :local)
      Application.delete_env(:tcm_mobile, :api_req_plug)
      if prev_env, do: System.put_env("TCM_API_SOURCE", prev_env)

      Mob.State.delete(:tcm_api_token)
      Api.clear_cache()
      TcmMobile.Store.reset()
    end)

    :ok
  end

  # ─── 数据源 ──────────────────────────────────────────────────────

  describe "source/0" do
    test "honours the :api_source config" do
      assert Api.source() == :remote

      Application.put_env(:tcm_mobile, :api_source, :local)
      assert Api.source() == :local
      assert Api.local?()
    end
  end

  # ─── 课程目录 ────────────────────────────────────────────────────

  describe "list_courses/1" do
    test "decodes a JSON:API catalog into course structs" do
      expect_catalog()

      assert [course] = Api.list_courses()
      assert course.id == @course_id
      assert course.title == "中医基础理论精讲"
      assert course.subtitle == "从阴阳五行到藏象经络"
      assert course.level == :beginner
      assert course.category_id == @category_id
      assert course.category == "basics"
      assert course.category_ref.name == "中医基础"
      assert course.lesson_count == 2
      assert course.teacher.name == "授课教师"
      assert course.progress == %{completed: [], total: 2, percent: 0}
    end

    test "flattens chapters into lessons, numbered across the whole course" do
      expect_catalog()

      assert [lesson_a, lesson_b] = hd(Api.list_courses()).lessons
      assert lesson_a.no == 1
      assert lesson_a.chapter_no == 1
      assert lesson_a.title == "1.1 阴阳学说总论（试看）"
      assert lesson_a.kind == :text
      assert lesson_a.duration_min == 10
      assert lesson_a.content == ["# 阴阳学说", "阴阳是对立统一，是中医辨证的总纲。"]

      assert lesson_b.no == 2
      assert lesson_b.kind == :video
      assert lesson_b.content == nil
    end

    test "sends the JSON:API accept header" do
      test_pid = self()

      Req.Test.stub(:tcm_api, fn conn ->
        send(test_pid, {:headers, conn.req_headers})
        Req.Test.json(conn, catalog_body())
      end)

      _ = Api.list_courses()

      assert_received {:headers, headers}
      assert List.keyfind(headers, "accept", 0) == {"accept", @jsonapi}
      assert List.keyfind(headers, "authorization", 0) == {"authorization", "Bearer test-token"}
    end

    test "filters by the backend category id" do
      expect_catalog()

      assert [_] = Api.list_courses(@category_id)
      assert [] == Api.list_courses("basics")
    end

    test "is served from cache within the 15s TTL" do
      Req.Test.expect(:tcm_api, 1, fn conn -> Req.Test.json(conn, catalog_body()) end)

      assert [_] = Api.list_courses()
      assert [_] = Api.list_courses()
      assert [hit] = Api.search_courses("中医")
      assert hit.id == @course_id
      assert [] == Api.search_courses("阴阳")
    end

    test "falls back to the local catalog when the backend errors" do
      Req.Test.stub(:tcm_api, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert Api.list_courses() == Catalog.courses()
      assert Api.list_categories() == Catalog.categories()
    end

    test "stays local when there is no session token" do
      Mob.State.delete(:tcm_api_token)

      # 没有任何桩：真的发起 HTTP 会在这里抛 "no mock or stub"
      assert Api.list_courses() == Catalog.courses()
      assert Api.my_stats() == TcmMobile.Store.my_stats()
      assert Api.notifications() == TcmMobile.Store.notifications()
    end

    test "keeps the last good payload when a refresh fails" do
      Req.Test.expect(:tcm_api, 1, fn conn -> Req.Test.json(conn, catalog_body()) end)
      assert [_] = Api.list_courses()

      # 让缓存过期后再取一次：这次失败，应当退回上一次成功的结果
      expire_cache(:catalog)
      Req.Test.stub(:tcm_api, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

      assert [course] = Api.list_courses()
      assert course.id == @course_id
    end
  end

  # ─── 分类 / 热门 ─────────────────────────────────────────────────

  describe "list_categories/0" do
    test "derives unique categories from the remote catalog" do
      expect_catalog()

      assert [%{id: @category_id, name: "中医基础", icon: nil}] = Api.list_categories()
    end
  end

  describe "popular_courses/0" do
    test "takes the first ten remote courses" do
      expect_catalog()

      assert [%{id: @course_id}] = Api.popular_courses()
    end
  end

  # ─── 课程详情 ────────────────────────────────────────────────────

  describe "get_course/1" do
    test "fetches a backend course by id" do
      Req.Test.stub(:tcm_api, fn conn ->
        assert conn.request_path == "/api/student/courses/#{@course_id}"
        Req.Test.json(conn, %{"data" => course_resource(), "included" => shared_included()})
      end)

      course = Api.get_course(@course_id)
      assert course.title == "中医基础理论精讲"
      assert course.lesson_count == 2
    end

    test "a local id never leaves the device" do
      course = Api.get_course("c1")
      assert course.title == hd(Catalog.courses()).title
    end

    test "an unreachable backend uuid renders a placeholder instead of crashing" do
      Req.Test.stub(:tcm_api, fn conn -> Plug.Conn.send_resp(conn, 404, "gone") end)

      course = Api.get_course(@other_course_id)
      assert course.id == @other_course_id
      assert course.title == "课程暂不可用"
      assert course.lessons == []
    end
  end

  # ─── 我的选课 / 进度 ─────────────────────────────────────────────

  describe "my_courses/0" do
    test "turns enrollments into courses with progress percentages" do
      expect_enrollments()

      assert [course] = Api.my_courses()
      assert course.id == @course_id
      assert course.enrollment_id == @enrollment_id
      assert course.lesson_count == 2
      assert course.progress == %{completed: [@lesson_a], total: 2, percent: 50}
    end

    test "progress/1 and completed_lesson?/2 read from the same payload" do
      expect_enrollments()

      assert Api.progress(@course_id) == %{completed: [@lesson_a], total: 2, percent: 50}
      assert Api.completed_lesson?(@course_id, @lesson_a)
      refute Api.completed_lesson?(@course_id, @lesson_b)
    end

    test "enrolled?/1 is true for the remote enrollment and false otherwise" do
      expect_enrollments()

      assert Api.enrolled?(@course_id)
      refute Api.enrolled?(@other_course_id)
    end
  end

  describe "complete_lesson/2" do
    test "posts the whole progress contract with the JSON:API media type" do
      test_pid = self()

      # ① 先查 enrollments 拿 enrollment_id ② 再 POST progress
      Req.Test.stub(:tcm_api, fn conn ->
        if conn.method == "GET" do
          assert conn.request_path == "/api/student/enrollments"
          Req.Test.json(conn, enrollments_body())
        else
          assert conn.method == "POST"
          assert conn.request_path == "/api/student/progress"

          assert Plug.Conn.get_req_header(conn, "content-type") == [@jsonapi]
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-token"]

          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:progress, Jason.decode!(raw)})
          Req.Test.json(conn, progress_resource())
        end
      end)

      assert :ok == Api.complete_lesson(@course_id, @lesson_b)

      assert_received {:progress, body}
      attrs = get_in(body, ["data", "attributes"])

      # 带 default 的属性在 upsert 冲突分支会被整份覆盖，三个都必须显式上送
      assert attrs["enrollment_id"] == @enrollment_id
      assert attrs["lesson_id"] == @lesson_b
      assert attrs["status"] == "completed"
      assert attrs["progress_pct"] == 100
      assert attrs["last_position_seconds"] == 0
    end

    test "a local course id only writes to the local store" do
      assert {:ok, :enrolled} = Api.enroll("c1")
      assert :ok == Api.complete_lesson("c1", "c1-l1")
      assert Api.completed_lesson?("c1", "c1-l1")
    end
  end

  # ─── 首页统计 ────────────────────────────────────────────────────

  describe "my_stats/0" do
    test "maps the six overview counters" do
      Req.Test.stub(:tcm_api, fn conn ->
        assert conn.request_path == "/api/student/enrollments/overview"

        Req.Test.json(conn, %{
          "enrolled_courses" => 3,
          "completed_lessons" => 4,
          "study_seconds" => 2400,
          "streak_days" => 1,
          "mistakes" => 2,
          "unread_notifications" => 0
        })
      end)

      assert Api.my_stats() == %{
               courses: 3,
               lessons_done: 4,
               study_minutes: 40,
               streak: 1,
               mistakes: 2
             }
    end
  end

  # ─── 通知 ────────────────────────────────────────────────────────

  describe "notifications/0" do
    test "decodes notifications and counts the unread ones" do
      Req.Test.stub(:tcm_api, fn conn ->
        assert conn.request_path == "/api/student/notifications"

        Req.Test.json(conn, %{
          "data" => [
            notification_resource("n1", "课程已发布", nil),
            notification_resource("n2", "选课成功", "2026-09-27T12:30:32Z")
          ]
        })
      end)

      assert [first, second] = Api.notifications()
      assert first.title == "课程已发布"
      refute first.read
      # time 一律取 inserted_at（未读时没有 read_at）
      assert first.time == "2026-10-06 01:41"

      assert second.read
      assert second.time == "2026-10-06 01:41"
      assert Api.unread_count() == 1
    end

    test "falls back to the local notifications when the backend errors" do
      Req.Test.stub(:tcm_api, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert Api.notifications() == TcmMobile.Store.notifications()
    end
  end

  # ─── 考试记录 ────────────────────────────────────────────────────

  describe "my_exam_records/0" do
    test "joins the assignment with its included exam" do
      Req.Test.stub(:tcm_api, fn conn ->
        assert conn.request_path == "/api/student/exam-assignments"

        Req.Test.json(conn, %{
          "data" => [
            %{
              "id" => "96e46f0e-8afe-45c2-bdf9-a2982d4ea57a",
              "type" => "exam_assignment",
              "attributes" => %{
                "exam_id" => @other_course_id,
                "status" => "graded",
                "total_score" => 30.0,
                "assigned_at" => "2026-09-27T12:30:32Z",
                "graded_at" => "2026-09-27T12:38:53Z"
              }
            }
          ],
          "included" => [
            %{
              "id" => @other_course_id,
              "type" => "exam",
              "attributes" => %{"name" => "期中测验", "duration_minutes" => 60}
            }
          ]
        })
      end)

      assert [record] = Api.my_exam_records()
      assert record.exam_name == "期中测验"
      assert record.status == "graded"
      assert record.score == 30.0
      assert record.assigned_at == "2026-09-27T12:30:32Z"
    end

    test "an empty list when the backend errors" do
      Req.Test.stub(:tcm_api, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert Api.my_exam_records() == []
    end
  end

  # ─── 选课写入 ────────────────────────────────────────────────────

  describe "enroll/1" do
    test "posts a JSON:API document for a backend uuid" do
      test_pid = self()

      Req.Test.stub(:tcm_api, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/student/enrollments"

        assert Plug.Conn.get_req_header(conn, "content-type") == [@jsonapi]
        assert Plug.Conn.get_req_header(conn, "accept") == [@jsonapi]

        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:enroll, Jason.decode!(raw)})

        Req.Test.json(conn, %{
          "data" => %{"type" => "enrollment", "id" => "e1", "attributes" => %{}}
        })
      end)

      assert {:ok, :enrolled} = Api.enroll(@course_id)

      assert_received {:enroll, body}
      assert get_in(body, ["data", "type"]) == "enrollment"
      assert get_in(body, ["data", "attributes", "course_id"]) == @course_id
    end

    test "a local id only writes to the store and never hits HTTP" do
      # 没有桩：发起 HTTP 会抛 "no mock or stub"
      assert {:ok, :enrolled} = Api.enroll("c1")
      assert Api.enrolled?("c1")
      refute Api.enrolled?("c2")
    end
  end

  # ─── helpers ─────────────────────────────────────────────────────

  # 让下一次读重新走网络（`:persistent_term` 里直接把时间戳拨老）
  defp expire_cache(key) do
    case :persistent_term.get({TcmMobile.Api, :cache, key}, nil) do
      {_ts, value} ->
        old = System.monotonic_time(:millisecond) - 60_000
        :persistent_term.put({TcmMobile.Api, :cache, key}, {old, value})

      nil ->
        :ok
    end
  end

  defp expect_catalog do
    Req.Test.stub(:tcm_api, fn conn ->
      assert conn.request_path == "/api/student/courses"
      Req.Test.json(conn, catalog_body())
    end)
  end

  defp expect_enrollments do
    Req.Test.stub(:tcm_api, fn conn ->
      assert conn.request_path == "/api/student/enrollments"
      Req.Test.json(conn, enrollments_body())
    end)
  end

  defp catalog_body do
    %{"data" => [course_resource()], "included" => shared_included()}
  end

  defp course_resource do
    %{
      "id" => @course_id,
      "type" => "course",
      "attributes" => %{
        "title" => "中医基础理论精讲",
        "subtitle" => "从阴阳五行到藏象经络",
        "description" => "本课程覆盖中医基础理论核心。",
        "level" => "beginner",
        "tags" => ["中医"],
        "price_cents" => 0,
        "status" => "published",
        "category_id" => @category_id
      }
    }
  end

  defp shared_included do
    [
      %{
        "id" => @category_id,
        "type" => "course_category",
        "attributes" => %{
          "name" => "中医基础",
          "slug" => "basics",
          "icon" => nil,
          "sort_order" => 1
        }
      },
      %{
        "id" => @chapter_id,
        "type" => "chapter",
        "attributes" => %{"course_id" => @course_id, "title" => "第一章", "sort_order" => 1}
      },
      %{
        "id" => @lesson_a,
        "type" => "lesson",
        "attributes" => %{
          "chapter_id" => @chapter_id,
          "title" => "1.1 阴阳学说总论（试看）",
          "content_type" => "article",
          "duration_seconds" => 600,
          "content_text" => "# 阴阳学说\n阴阳是对立统一，是中医辨证的总纲。",
          "sort_order" => 1
        }
      },
      %{
        "id" => @lesson_b,
        "type" => "lesson",
        "attributes" => %{
          "chapter_id" => @chapter_id,
          "title" => "1.2 五行学说与藏象",
          "content_type" => "video",
          "duration_seconds" => 600,
          "content_text" => nil,
          "sort_order" => 2
        }
      }
    ]
  end

  defp enrollments_body do
    %{
      "data" => [
        %{
          "id" => @enrollment_id,
          "type" => "enrollment",
          "attributes" => %{"course_id" => @course_id, "status" => "active"},
          "relationships" => %{
            "progress_records" => %{"data" => [%{"type" => "progress", "id" => "p1"}]}
          }
        }
      ],
      "included" =>
        shared_included() ++
          [
            %{
              "id" => @course_id,
              "type" => "course",
              "attributes" => course_resource()["attributes"]
            },
            %{
              "id" => "p1",
              "type" => "progress",
              "attributes" => %{
                "enrollment_id" => @enrollment_id,
                "lesson_id" => @lesson_a,
                "status" => "completed",
                "progress_pct" => 100,
                "last_position_seconds" => 600
              }
            }
          ]
    }
  end

  defp progress_resource do
    %{
      "data" => %{
        "id" => "p2",
        "type" => "progress",
        "attributes" => %{
          "enrollment_id" => @enrollment_id,
          "lesson_id" => @lesson_b,
          "status" => "completed",
          "progress_pct" => 100,
          "last_position_seconds" => 0
        }
      }
    }
  end

  defp notification_resource(id, title, read_at) do
    %{
      "id" => id,
      "type" => "notification",
      "attributes" => %{
        "title" => title,
        "body" => "",
        "inserted_at" => "2026-10-06T01:41:00Z",
        "read_at" => read_at
      }
    }
  end
end
