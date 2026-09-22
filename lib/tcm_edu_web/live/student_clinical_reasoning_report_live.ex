defmodule TcmEduWeb.StudentClinicalReasoningReportLive do
  @moduledoc """
  学生端「临床思维能力报告」页 at `/simulated-patient/report`.

  汇总该学生在周期内已完成会话的 `Evaluation`（含诊断准确性/鉴别全面性/
  治疗合理性等维度），用 `AI.ReasoningReportGenerator` 聚合六维能力分，并
  生成个性化提升计划，可保存为 `ClinicalReasoningReport` 供历史回顾。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.AI.ReasoningReportGenerator
  alias TcmEdu.SimulatedPatient.{ClinicalReasoningReport, Evaluation}

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    student = socket.assigns.current_student
    evaluations = list_completed_evaluations(student)
    dimensions = ReasoningReportGenerator.compute_dimensions(evaluations)

    socket =
      socket
      |> assign(:page_title, "临床思维报告")
      |> assign(:evaluations, evaluations)
      |> assign(:dimensions, dimensions)
      |> assign(:report, latest_report(student))
      |> assign(:generating, false)
      |> assign(:run_ref, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("generate", _params, socket) do
    cond do
      socket.assigns.generating ->
        {:noreply, socket}

      socket.assigns.evaluations == [] ->
        {:noreply, put_flash(socket, :info, "暂无已评分的会话，先完成一次全流程模拟吧")}

      true ->
        do_generate(socket)
    end
  end

  @impl true
  def handle_info({:report_done, ref, result}, socket) do
    if ref == socket.assigns.run_ref do
      student = socket.assigns.current_student

      case persist_report(result, socket.assigns.dimensions, student) do
        {:ok, report} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> assign(:run_ref, nil)
           |> assign(:report, report)
           |> put_flash(:info, "报告已生成并保存")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> assign(:run_ref, nil)
           |> put_flash(:error, "报告保存失败：#{reason}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:report_error, ref, message}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:generating, false)
       |> assign(:run_ref, nil)
       |> put_flash(:error, "AI 出错了：#{message}")}
    else
      {:noreply, socket}
    end
  end

  # ── helpers ───────────────────────────────────────────────

  defp list_completed_evaluations(student) do
    Evaluation
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(student_id == ^student.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, evals} -> evals
      _ -> []
    end
  rescue
    _ -> []
  end

  defp latest_report(student) do
    ClinicalReasoningReport
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(student_id == ^student.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, report} -> report
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp do_generate(socket) do
    _student = socket.assigns.current_student
    lv = self()
    ref = make_ref()

    Task.start(fn ->
      case generate_report(socket.assigns.evaluations) do
        {:ok, result} ->
          if Process.alive?(lv), do: send(lv, {:report_done, ref, result})

        {:error, reason} ->
          if Process.alive?(lv),
            do: send(lv, {:report_error, ref, "报告生成失败（#{inspect(reason)}）"})
      end
    end)

    {:noreply, socket |> assign(:generating, true) |> assign(:run_ref, ref)}
  end

  defp generate_report(evaluations) do
    evals = Enum.map(evaluations, &evaluation_to_attrs/1)
    dims = ReasoningReportGenerator.compute_dimensions(evals)
    weaknesses = collect_weaknesses(evaluations)

    with {:ok, plan} <-
           ReasoningReportGenerator.improvement_plan(dimensions: dims, weaknesses: weaknesses) do
      {:ok,
       %{
         dims: dims,
         improvement_plan: plan.improvement_plan,
         dimension_report: plan.dimension_report
       }}
    end
  end

  defp evaluation_to_attrs(evaluations) do
    %{
      diagnosis_score: evaluations.diagnosis_score,
      differential_score: evaluations.differential_score,
      treatment_score: evaluations.treatment_score,
      stage_scores: evaluations.stage_scores || %{}
    }
  end

  defp collect_weaknesses(evaluations) do
    evaluations
    |> Enum.flat_map(fn e -> e.weaknesses || [] end)
    |> Enum.take(8)
  end

  defp persist_report(result, _dims, student) do
    attrs = %{
      student_id: student.id,
      report_period_start: Date.add(Date.utc_today(), -30),
      report_period_end: Date.utc_today(),
      inquiry_score: result.dims.inquiry || 0,
      physical_exam_score: result.dims.physical_exam || 0,
      auxiliary_score: result.dims.auxiliary || 0,
      diagnosis_score: result.dims.diagnosis || 0,
      differential_score: result.dims.differential || 0,
      treatment_score: result.dims.treatment || 0,
      follow_up_score: result.dims.follow_up || 0,
      total_score: Decimal.from_float(result.dims.total) |> Decimal.round(1),
      grade: result.dims.grade,
      session_count: result.dims.session_count,
      improvement_plan: result.improvement_plan,
      dimension_report: result.dimension_report,
      generated_at: DateTime.utc_now()
    }

    ClinicalReasoningReport
    |> Ash.Changeset.for_create(:create, attrs, actor: student.actor, tenant: student.tenant)
    |> Ash.create()
    |> case do
      {:ok, report} -> {:ok, report}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  # ── render ────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:simulated_patient}>
        <div class="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h1 class="text-xl font-semibold">我的临床思维能力报告</h1>
              <p class="mt-1 text-sm text-base-content/60">
               　基于 {length(@evaluations)} 次已评分会话，聚合诊断准确性、鉴别诊断全面性、治疗合理性等维度。
              </p>
            </div>
            <button
              type="button"
              id="generate-report"
              phx-click="generate"
              class="btn btn-primary btn-sm"
              disabled={@generating or @evaluations == []}
            >
              <span :if={@generating} class="loading loading-spinner loading-xs" aria-hidden="true" />
              {if @generating, do: "生成中…", else: "生成本期 AI 报告"}
            </button>
          </div>

          <div class="mt-4 grid items-start gap-4 lg:grid-cols-3">
            <div class="card border border-base-300 bg-base-100 lg:col-span-1">
              <div class="card-body gap-3 p-4">
                <p class="font-medium">能力分</p>
                <div class="flex flex-col items-center gap-1 border-b border-base-300 pb-3">
                  <p class="text-5xl font-semibold tabular-nums">{@dimensions.total}</p>
                  <span class="badge badge-soft badge-sm">{grade_label(@dimensions.grade)}</span>
                </div>
                <div class="flex flex-col gap-2">
                  <.dim_row label="问诊完整度" value={@dimensions.inquiry} />
                  <.dim_row label="查体规范度" value={@dimensions.physical_exam} />
                  <.dim_row label="检查合理性" value={@dimensions.auxiliary} />
                  <.dim_row label="诊断准确性" value={@dimensions.diagnosis} />
                  <.dim_row label="鉴别诊断全面性" value={@dimensions.differential} />
                  <.dim_row label="治疗合理性" value={@dimensions.treatment} />
                  <.dim_row label="随访把握" value={@dimensions.follow_up} />
                </div>
              </div>
            </div>

            <div class="card border border-base-300 bg-base-100 lg:col-span-2">
              <div class="card-body gap-3 p-4">
                <p class="font-medium">AI 提升计划与短板分析</p>

                <div :if={@report} class="flex flex-col gap-3">
                  <p :if={@report.improvement_plan != ""} class="whitespace-pre-line text-sm leading-6 rounded-box bg-base-200/30 p-3">
                    {@report.improvement_plan}
                  </p>

                  <div :if={@report.dimension_report != %{}} class="grid items-start gap-2 md:grid-cols-3">
                    <.dim_detail report={@report.dimension_report} dim={:diagnosis} />
                    <.dim_detail report={@report.dimension_report} dim={:differential} />
                    <.dim_detail report={@report.dimension_report} dim={:treatment} />
                  </div>
                </div>

                <p :if={is_nil(@report) and @evaluations != []} class="text-sm text-base-content/60">
                  点击右上角「生成本期 AI 报告」生成提升计划。
                </p>

                <p :if={@evaluations == []} class="py-6 text-center text-sm text-base-content/60">
                  暂无已评分的会话。完成一次全流程临床模拟并结束评分后再来生成报告。
                </p>
              </div>
            </div>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, default: nil

  defp dim_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between text-sm">
      <span class="text-base-content/70">{@label}</span>
      <span :if={@value} class="font-semibold tabular-nums">{@value}</span>
      <span :if={is_nil(@value)} class="text-base-content/40">无数据</span>
    </div>
    """
  end

  attr :report, :map, required: true
  attr :dim, :atom, required: true

  defp dim_detail(assigns) do
    assigns = assign(assigns, :item, assigns.report[assigns.dim])

    ~H"""
    <div :if={@item} class="rounded-box border border-base-300 bg-base-200/30 p-3">
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium">{ReasoningReportGenerator.dim_label(@dim)}</p>
        <span class="text-lg font-semibold tabular-nums">{@item.score}</span>
      </div>
      <p :if={@item.gap != ""} class="mt-1 text-xs text-warning">短板：{@item.gap}</p>
      <p :if={@item.suggestion != ""} class="mt-1 text-xs text-base-content/70">建议：{@item.suggestion}</p>
    </div>
    """
  end

  defp grade_label(:excellent), do: "优秀"
  defp grade_label(:good), do: "良好"
  defp grade_label(:pass), do: "及格"
  defp grade_label(:borderline), do: "边缘"
  defp grade_label(:fail), do: "待提升"
  defp grade_label(_), do: "—"
end
