defmodule TcmMobile.ScreensTest do
  use Mob.ScreenCase

  alias TcmMobile.Screens
  alias TcmMobile.Store

  setup do
    Store.reset()
    :ok
  end

  test "welcome screen mounts and renders a login CTA" do
    view = mount_screen(Screens.WelcomeScreen)
    assert text(view) =~ "杏宁树"
    assert find(view, :button, text: "学员登录")
    assert_renderable(view)
  end

  test "login screen renders the demo hint" do
    view = mount_screen(Screens.LoginScreen)
    assert text(view) =~ "演示账号"
    assert_renderable(view)
  end

  test "home screen renders stats and popular courses" do
    view = mount_screen(Screens.HomeScreen)
    assert assigns(view).popular != []
    assert text(view) =~ "热门课程"
    assert_renderable(view)
  end

  test "courses screen renders course cards" do
    view = mount_screen(Screens.CoursesScreen)
    assert assigns(view).courses != []
    assert text(view) =~ "中医基础理论精讲"
    assert_renderable(view)
  end

  test "course detail screen shows lessons" do
    view = mount_screen(Screens.CourseDetailScreen, %{course_id: "c1"})
    assert assigns(view).course.lessons != []
    assert text(view) =~ "中医基础理论精讲"
    assert_renderable(view)
  end

  test "exams screen lists three exams" do
    view = mount_screen(Screens.ExamsScreen)

    assert text(view) =~ "中医基础·阶段性测验（一）"
    assert text(view) =~ "中药方剂综合测验"
    assert text(view) =~ "临床辨证·期末考试"
    assert text(view) =~ "测验 ·"
    assert text(view) =~ "考试 ·"
    assert text(view) =~ "未开始"
    assert_renderable(view)
  end

  test "exam take screen can answer and submit" do
    view = mount_screen(Screens.ExamTakeScreen, %{exam_id: "e1"})

    exam = assigns(view).exam

    view =
      Enum.reduce(exam.questions, view, fn q, acc ->
        render_info(acc, {:tap, {:answer, q.id, q.answer}})
      end)

    view = render_info(view, {:tap, :submit_confirm})
    assert assigns(view).result.score == 100
    assert text(view) =~ "测验结果"
    assert text(view) =~ "参考答案"
  end

  test "exam take screen refuses to submit while questions are unanswered" do
    view = mount_screen(Screens.ExamTakeScreen, %{exam_id: "e1"})

    [first | _] = assigns(view).exam.questions
    view = render_info(view, {:tap, {:answer, first.id, first.answer}})

    view = render_info(view, {:tap, :submit_confirm})

    refute assigns(view).result
    assert assigns(view).notice =~ "未作答"
    assert text(view) =~ "未作答"
  end

  test "fill question renders a text input with its no-score hint" do
    view = mount_screen(Screens.ExamTakeScreen, %{exam_id: "e1"})

    exam = assigns(view).exam
    fill_at = Enum.find_index(exam.questions, &(&1.type == :fill))

    view =
      Enum.reduce(0..(fill_at - 1)//1, view, fn _, acc -> render_info(acc, {:tap, :next}) end)

    assert text(view) =~ "填空、问答题不计分"
  end

  test "chat screen sends a message and gets an AI reply" do
    view = mount_screen(Screens.ChatScreen)
    view = render_info(view, {:change, :draft, "什么是五行？"})
    view = render_info(view, {:tap, :send})

    assert length(assigns(view).messages) == 2
    assert text(view) =~ "五行"
  end

  test "simulated patient session starts and completes with report link" do
    Store.login("student@tcm.edu.cn", "123456")

    view = mount_screen(Screens.SimulatedPatientSessionScreen, %{patient_id: "sp1"})
    assert find(view, :button, text: "开始接诊")

    view = render_info(view, {:tap, :start})
    assert assigns(view).session.status == :in_progress

    sp = TcmMobile.Data.Catalog.simulated_patient("sp1")
    view = render_info(view, {:tap, {:dialectic, sp.correct_dialectic}})
    view = render_info(view, {:tap, :submit_dialectic})

    assert assigns(view).session.status == :completed
    assert find(view, :button, text: "查看临床推理报告")
  end

  test "MDT room shows participants and accepts a post" do
    view = mount_screen(Screens.MdtRoomScreen, %{room_id: "m1"})
    assert text(view) =~ "参与医师"

    view = render_info(view, {:change, :draft, "我建议结合四诊进一步辨证。"})
    view = render_info(view, {:tap, :send})

    assert length(assigns(view).data.messages) > 3
  end

  test "mistakes screen shows the mistake book" do
    Store.login("student@tcm.edu.cn", "123456")
    view = mount_screen(Screens.MistakesScreen)
    assert_renderable(view)
  end

  test "learning tab shows enrolled courses with progress" do
    Store.login("student@tcm.edu.cn", "123456")
    Store.enroll("c1")
    view = mount_screen(Screens.LearningScreen)
    assert length(assigns(view).courses) == 1
    assert_renderable(view)
  end

  test "profile screen greets the logged-in student" do
    Store.login("student@tcm.edu.cn", "123456")
    view = mount_screen(Screens.ProfileScreen)
    assert text(view) =~ "李明"
    assert_renderable(view)
  end
end
