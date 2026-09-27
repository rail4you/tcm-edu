defmodule TcmEdu.Workers.NotificationDeliver do
  @moduledoc """
  Oban worker 异步创建站内通知。

  由于 `Notification` 是 `multitenancy :context` 的资源，job args 必须携带
  `tenant`（形如 `"tenant_<slug>"`），worker 内显式 setting tenant。

  ## 用法

      TcmEdu.Workers.NotificationDeliver.new(%{
        tenant: "tenant_default",
        recipient_id: user_id,
        actor_id:  actor_id,
        type:      "course_published",
        title:     "《中医基础》已发布",
        body:      "……",
        payload:   %{course_id: course_id, route: "/course/<id>"}
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query

  alias TcmEdu.Notification.Notification

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    tenant = args["tenant"]

    type = string_to_type(args["type"])

    attrs = %{
      recipient_id: args["recipient_id"],
      actor_id: args["actor_id"],
      type: type,
      title: args["title"],
      body: args["body"],
      payload: args["payload"] || %{}
    }

    case Notification
         |> Ash.Changeset.for_action(:notify, attrs, tenant: tenant)
         |> Ash.create(authorize?: false) do
      {:ok, %Notification{}} -> :ok
      {:error, error} -> {:error, inspect(error)}
    end
  end

  # 安全地把字符串转成允许的通知类型 atom，未知类型回退 :system，
  # 避免 String.to_atom/1 的内存泄漏风险。
  defp string_to_type(nil), do: :system

  defp string_to_type(type) when is_atom(type), do: type

  defp string_to_type(type) when is_binary(type) do
    case type do
      "system" -> :system
      "enrollment" -> :enrollment
      "course_published" -> :course_published
      "progress" -> :progress
      "quiz_graded" -> :quiz_graded
      "ai_lesson" -> :ai_lesson
      "exam_generated" -> :exam_generated
      "exam_assigned" -> :exam_assigned
      "exam_graded" -> :exam_graded
      _ -> :system
    end
  end
end
