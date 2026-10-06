defmodule TcmEdu.Enrollment.Overview do
  @moduledoc """
  学员首页统计 —— `GET /api/student/enrollments/overview` 的实现。

  对应 `TcmEdu.Enrollment.Enrollment` 上的 generic action `:overview`：一次请求
  算完移动端首页要的 6 个数字，免得客户端串行发四五个 JSON:API 请求再自己拼。

  每条查询都同时带 `actor` + `tenant`，并显式加属主过滤（policy 再收口一层），
  保证学生只能统计到自己的数据。
  """

  use Ash.Resource.Actions.Implementation

  alias TcmEdu.Enrollment.{Enrollment, Progress}
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Quiz.Attempt

  require Ash.Query

  @impl true
  def run(_input, _opts, %{actor: nil}), do: {:error, "未登录"}

  def run(_input, _opts, context) do
    actor = context.actor
    tenant = context.tenant

    with {:ok, completed} <- completed_progress(actor, tenant),
         {:ok, enrolled} <- count(active_enrollments(actor), actor, tenant),
         {:ok, mistakes} <- count(mistakes(actor), actor, tenant),
         {:ok, unread} <- count(unread_notifications(actor), actor, tenant) do
      {:ok,
       %{
         enrolled_courses: enrolled,
         completed_lessons: length(completed),
         study_seconds: completed |> Enum.map(&lesson_seconds/1) |> Enum.sum(),
         streak_days: streak_days(completed),
         mistakes: mistakes,
         unread_notifications: unread
       }}
    end
  end

  # 已完成的课时（含 lesson 以便累加时长、按 completed_at 排连续天数）
  defp completed_progress(actor, tenant) do
    Progress
    |> Ash.Query.filter(status == :completed)
    |> Ash.Query.filter(enrollment.user_id == ^actor.id)
    |> Ash.Query.load(:lesson)
    |> Ash.read(actor: actor, tenant: tenant)
  end

  defp active_enrollments(actor) do
    Enrollment
    |> Ash.Query.filter(user_id == ^actor.id and status == :active)
  end

  defp mistakes(actor) do
    Attempt
    |> Ash.Query.filter(user_id == ^actor.id and is_correct == false)
  end

  defp unread_notifications(actor) do
    Notification
    |> Ash.Query.filter(recipient_id == ^actor.id and is_nil(read_at))
  end

  defp count(query, actor, tenant) do
    Ash.count(query, actor: actor, tenant: tenant)
  end

  defp lesson_seconds(%{lesson: %Ash.NotLoaded{}}), do: 0
  defp lesson_seconds(%{lesson: nil}), do: 0
  defp lesson_seconds(%{lesson: lesson}), do: lesson.duration_seconds || 0

  # 连续学习天数：以最近一次完成日为锚点往回数，断更则为 0。
  # 今天还没打卡时，只要昨天打过卡仍算连续（避免每天早上掉回 0）。
  defp streak_days(records) do
    records
    |> Enum.map(& &1.completed_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&DateTime.to_date/1)
    |> Enum.uniq()
    |> Enum.sort(fn a, b -> Date.compare(a, b) != :gt end)
    |> reduce_streak(Date.utc_today())
  end

  defp reduce_streak([], _today), do: 0

  defp reduce_streak([latest | _] = dates, today) do
    if Date.diff(today, latest) > 1 do
      0
    else
      dates
      |> Enum.reduce_while({0, latest}, fn date, {count, expected} ->
        if Date.compare(date, expected) == :eq do
          {:cont, {count + 1, Date.add(expected, -1)}}
        else
          {:halt, {count, expected}}
        end
      end)
      |> elem(0)
    end
  end
end
