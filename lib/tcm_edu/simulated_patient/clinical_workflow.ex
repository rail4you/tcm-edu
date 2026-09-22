defmodule TcmEdu.SimulatedPatient.ClinicalWorkflow do
  @moduledoc """
  全流程临床模拟的阶段定义与难度分级配置（纯数据域模块，确定性、可单测）。

  定义七阶段流程：

    * `:inquiry`        — 问诊
    * `:physical_exam`  — 体格检查
    * `:auxiliary`      — 辅助检查
    * `:diagnosis`      — 诊断
    * `:differential`   — 鉴别诊断
    * `:treatment`      — 治疗方案
    * `:follow_up`      — 随访

  以及四档难度分级（对应 `Patient.difficulty_level`）的推进与标注策略：

    * `:introductory` — 入门：典型病例、线性推进、高提示、无 red flag 强约束
    * `:advanced`     — 进阶：复杂病例、路径分叉、中提示
    * `:expert`       — 专家：疑难杂症、多分支、允许部分顺序弹性、低提示
    * `:emergency`    — 急诊：危重病例、先救命后诊断、red flag 强约束

  由 `AI.ClinicalReasoning` 引擎与实时对比/评分器使用。
  """

  @stages [
    :inquiry,
    :physical_exam,
    :auxiliary,
    :diagnosis,
    :differential,
    :treatment,
    :follow_up
  ]

  @stage_labels %{
    inquiry: "问诊",
    physical_exam: "体格检查",
    auxiliary: "辅助检查",
    diagnosis: "诊断",
    differential: "鉴别诊断",
    treatment: "治疗方案",
    follow_up: "随访"
  }

  @stage_orders @stages |> Enum.with_index(1) |> Map.new(fn {s, i} -> {s, i} end)
  @orders_to_stages @stages |> Enum.with_index(1) |> Map.new(fn {s, i} -> {i, s} end)

  @difficulty_configs %{
    introductory: %{
      label: "入门",
      hint_level: :high,
      gating: :strict,
      elastic_order?: false,
      red_flag_strict?: false,
      min_stages_finish: 7
    },
    advanced: %{
      label: "进阶",
      hint_level: :medium,
      gating: :branch,
      elastic_order?: false,
      red_flag_strict?: false,
      min_stages_finish: 7
    },
    expert: %{
      label: "专家",
      hint_level: :low,
      gating: :branch,
      elastic_order?: true,
      red_flag_strict?: false,
      min_stages_finish: 7
    },
    emergency: %{
      label: "急诊",
      hint_level: :none,
      gating: :elastic,
      elastic_order?: true,
      red_flag_strict?: true,
      min_stages_finish: 6
    }
  }

  @doc "七阶段顺序列表（问诊 → … → 随访）"
  @spec stages() :: [atom()]
  def stages, do: @stages

  @doc "阶段的中文标签"
  @spec label(atom()) :: String.t()
  def label(stage), do: Map.get(@stage_labels, stage, to_string(stage))

  @doc "阶段顺序号（问诊=1 … 随访=7）"
  @spec order_of(atom()) :: pos_integer()
  def order_of(stage), do: Map.fetch!(@stage_orders, stage)

  @doc "按顺序号取阶段"
  @spec stage_at(pos_integer()) :: atom()
  def stage_at(order), do: Map.fetch!(@orders_to_stages, order)

  @doc "难度分级的中文标签"
  @spec difficulty_label(atom()) :: String.t()
  def difficulty_label(level) do
    get_in(@difficulty_configs, [level, :label]) || to_string(level)
  end

  @doc "难度分级配置。未知 level 回退到 :introductory"
  @spec difficulty_config(atom()) :: map()
  def difficulty_config(level) do
    Map.get(@difficulty_configs, level) || Map.get(@difficulty_configs, :introductory)
  end

  @doc "全部难度分级 keys"
  @spec difficulty_levels() :: [atom()]
  def difficulty_levels, do: Map.keys(@difficulty_configs)

  @doc "根据难度决定是否允许跨阶段顺序弹性（急诊/专家可先处理再补）"
  @spec elastic_order?(atom()) :: boolean()
  def elastic_order?(level), do: difficulty_config(level).elastic_order?

  @doc "急诊/危重症是否启用 red flag 强约束警示"
  @spec red_flag_strict?(atom()) :: boolean()
  def red_flag_strict?(level), do: difficulty_config(level).red_flag_strict?

  @doc "难度对应的现有 difficulty 数值区间（1-5）映射"
  @spec difficulty_range(atom()) :: Range.t()
  def difficulty_range(:introductory), do: 1..2
  def difficulty_range(:advanced), do: 3..3
  def difficulty_range(:expert), do: 4..4
  def difficulty_range(:emergency), do: 5..5
  def difficulty_range(_), do: 1..5

  @doc "生成某病例的七阶段初始描述（供创建 CaseStage 使用）"
  @spec build_stage_descriptors(map()) :: [map()]
  def build_stage_descriptors(patient) do
    level = normalize_level(patient[:difficulty_level] || patient["difficulty_level"])
    elastic = elastic_order?(level)

    @stages
    |> Enum.map(fn stage ->
      order = order_of(stage)

      status =
        cond do
          # 急诊：先救命，七阶段全部同时可操作（顺序弹性交给阶段机与评分器）
          elastic and level == :emergency -> :available
          # 顺序弹性的专家：问诊 + 查体同时可操作
          elastic and order <= 2 -> :available
          # 其余：仅第一阶段可用，逐级解锁
          order == 1 -> :available
          true -> :locked
        end

      %{stage: stage, order: order, status: status}
    end)
  end

  defp normalize_level(nil), do: nil
  defp normalize_level(l) when l in [:introductory, :advanced, :expert, :emergency], do: l
  defp normalize_level(l) when is_binary(l), do: String.to_existing_atom(l)
  defp normalize_level(_), do: nil
end