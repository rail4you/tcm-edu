defmodule TcmEdu.Notification.NotificationTest do
  @moduledoc """
  通知域测试（Phase 5 新资源骨架）：
    * 创建通知 / 列出只属于本人
    * mark_read / mark_all_read / unread_count
    * 权限：本人可读与标记；他人不可见；学生不能创建
    * Oban worker 异步投递（NotificationDeliver）
    * 跨租户隔离
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Workers.NotificationDeliver

  @tenant "tenant_default"

  describe "notification" do
    test "teacher creates a notification for a student; student sees only own" do
      teacher = create_user!(:teacher)
      student = create_user!(:student)
      other = create_user!(:student)

      assert {:ok, %Notification{title: "课程已发布"}} =
               notify!(teacher,
                 recipient_id: student.id,
                 actor_id: teacher.id,
                 type: :course_published,
                 title: "课程已发布",
                 body: "《中医基础》已上线",
                 payload: %{"route" => "/course/1"}
               )

      mine =
        Notification
        |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
        |> Ash.read!()

      assert length(mine) == 1
      assert hd(mine).recipient_id == student.id

      # 他人不可见
      others =
        Notification
        |> Ash.Query.for_read(:read, %{}, actor: other, tenant: @tenant)
        |> Ash.read!()

      assert others == []
    end

    test "mark_read sets read_at; unread_count decrements" do
      teacher = create_user!(:teacher)
      student = create_user!(:student)

      {:ok, n} = notify!(teacher, recipient_id: student.id, title: "A")
      {:ok, _} = notify!(teacher, recipient_id: student.id, title: "B")

      assert unread_count(student) == 2

      {:ok, %Notification{read_at: read_at}} =
        n
        |> Ash.Changeset.for_update(:mark_read, %{})
        |> Ash.update(actor: student, tenant: @tenant)

      assert read_at != nil
      assert unread_count(student) == 1
    end

    test "mark_all_read marks all of the actor's unread notifications" do
      teacher = create_user!(:teacher)
      student = create_user!(:student)

      for i <- 1..3, do: notify!(teacher, recipient_id: student.id, title: "N#{i}")

      assert unread_count(student) == 3

      Notification
      |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
      |> Ash.Query.filter(is_nil(read_at))
      |> Ash.read!(actor: student, tenant: @tenant)
      |> Enum.each(fn n ->
        n
        |> Ash.Changeset.for_update(:mark_read, %{})
        |> Ash.update(actor: student, tenant: @tenant)
      end)

      assert unread_count(student) == 0
    end

    test "student cannot create a notification" do
      student = create_user!(:student)

      assert {:error, %Ash.Error.Forbidden{}} =
               Notification
               |> Ash.Changeset.for_action(:notify, %{recipient_id: student.id, title: "X"},
                 actor: student,
                 tenant: @tenant
               )
               |> Ash.create()
    end

    test "NotificationDeliver worker creates a notification" do
      teacher = create_user!(:teacher)
      student = create_user!(:student)

      job = %Oban.Job{
        args: %{
          "tenant" => @tenant,
          "recipient_id" => student.id,
          "actor_id" => teacher.id,
          "type" => "course_published",
          "title" => "异步通知",
          "body" => "来自 worker"
        }
      }

      assert :ok == NotificationDeliver.perform(job)

      list =
        Notification
        |> Ash.Query.for_read(:read, %{}, actor: student, tenant: @tenant)
        |> Ash.read!()

      assert Enum.any?(list, &(&1.title == "异步通知"))
    end
  end

  # ─── helpers ───────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "notif-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp notify!(actor, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:type, :system)

    Notification
    |> Ash.Changeset.for_action(:notify, attrs, actor: actor, tenant: @tenant)
    |> Ash.create()
  end

  defp unread_count(user) do
    Notification
    |> Ash.Query.for_read(:unread_count, %{}, actor: user, tenant: @tenant)
    |> Ash.read!(actor: user, tenant: @tenant)
    |> length()
  end
end
