defmodule TcmEduWeb.AIController do
  @moduledoc """
  AI 能力控制器（合同 §1.6 · 计划 F2/F4/F5）：

    * `POST /api/ai/lesson_plan`      — 备课助手
    * `POST /api/ai/image`            — 医学图片生成（落库 OSS）
    * `POST /api/ai/mistake_explain`  — 错题解析（异步 Oban worker）

  通过 `:api_auth` pipeline，需要登录用户。
  """

  use TcmEduWeb, :controller

  alias TcmEdu.AI.{LessonPlan, MedicalImage}
  alias TcmEdu.Workers.MistakeExplainerWorker

  require Logger

  # ─── 备课助手 ────────────────────────────────────────

  def lesson_plan(conn, params) do
    topic = Map.get(params, "topic")

    if is_nil(topic) or topic == "" do
      render_error(conn, "missing topic", 400)
    else
      opts = [
        topic: topic,
        subject: Map.get(params, "subject", "医学"),
        level: Map.get(params, "level", "本科"),
        audience: Map.get(params, "audience")
      ]

      case LessonPlan.generate(opts) do
        {:ok, plan} -> json(conn, %{status: "ok", content: plan})
        {:error, reason} -> render_error(conn, reason, 422)
      end
    end
  end

  # ─── 医学图片生成（落库 OSS） ──────────────────────

  def image(conn, %{"prompt" => prompt} = params) do
    opts =
      [
        key_prefix: Map.get(params, "key_prefix", "ai"),
        style: Map.get(params, "style"),
        size: Map.get(params, "size"),
        n: Map.get(params, "n"),
        max_polls: Map.get(params, "max_polls"),
        interval_ms: Map.get(params, "interval_ms", 2_000)
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    case MedicalImage.generate_and_store(prompt, opts) do
      {:ok, urls} -> json(conn, %{status: "ok", urls: urls})
      {:error, reason} -> render_error(conn, reason, 502)
    end
  end

  def image(conn, _params), do: render_error(conn, "missing prompt", 400)

  # ─── 错题解析（异步） ──────────────────────────────

  def mistake_explain(conn, %{"attempt_id" => attempt_id}) do
    tenant = current_tenant(conn) || "tenant_default"

    case MistakeExplainerWorker.new(%{"tenant" => tenant, "attempt_id" => attempt_id})
         |> Oban.insert() do
      {:ok, _job} ->
        json(conn, %{status: "queued", attempt_id: attempt_id})

      {:error, reason} ->
        render_error(conn, reason, 422)
    end
  end

  def mistake_explain(conn, _params),
    do: render_error(conn, "missing attempt_id", 400)

  # ─── helpers ────────────────────────────────────────

  defp render_error(conn, reason, status) do
    Logger.warning("[AI] error #{inspect(reason)}")

    conn
    |> put_status(status)
    |> json(%{status: "error", reason: inspect(reason)})
  end

  defp current_tenant(conn) do
    case conn.assigns[:current_scope] do
      %{tenant: tenant} -> tenant
      _ -> nil
    end
  end
end
