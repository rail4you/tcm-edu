defmodule TcmEdu.SimulatedPatient.StageMachine do
  @moduledoc """
  阶段机：根据难度分级决定阶段解锁顺序（纯 Elixir，确定性、可单测）。

  规则：

    * 顺序推进（入门/进阶）：完成某阶段 → 解锁下一阶段
    * 顺序弹性（专家）：问诊完成同时解锁查体与辅助检查
    * 急诊（全解锁）：所有阶段初始即 available，由评分器按「先救命后诊断」
      的顺序弹性考核，这里只负责状态列表计算

  输入为 `ClinicalWorkflow.build_stage_descriptors/1` 输出的描述列表：
  `[%{stage:, order:, status:}]`。
  """

  alias TcmEdu.SimulatedPatient.ClinicalWorkflow

  @doc """
  完成指定阶段后，计算新的阶段状态列表。

  ## 参数

    * `descriptors` — `[%{stage:, order:, status:}]`
    * `completed`   — 刚完成的阶段原子
    * `level`       — 难度分级原子

  ## 返回

    * `{statuses, unlocked}` — 新描述列表（已完成的保持 completed），
      以及本次新解锁的阶段列表 `[atom()]`
  """
  @spec apply_completion([map()], atom(), atom()) :: {[map()], [atom()]}
  def apply_completion(descriptors, completed, level) do
    completed_order = ClinicalWorkflow.order_of(completed)
    elastic = ClinicalWorkflow.elastic_order?(level)

    descriptors
    |> Enum.reduce({[], []}, fn d, {statuses, unlocked} ->
      stage = d.stage
      order = d.order

      status =
        cond do
          stage == completed -> :completed
          d.status == :completed -> :completed
          d.status == :skipped -> :skipped
          d.status == :available -> :available
          # 顺序弹性（专家）：完成 1、2 阶段后，3 阶段也可解锁
          elastic and order <= completed_order + 1 -> :available
          # 普通顺序：只解锁下一个
          order == completed_order + 1 -> :available
          true -> :locked
        end

      new_d = Map.put(d, :status, status)

      unlocked =
        if status == :available and d.status != :available and d.status != :completed do
          [stage | unlocked]
        else
          unlocked
        end

      {[new_d | statuses], unlocked}
    end)
    |> then(fn {statuses, unlocked} -> {Enum.reverse(statuses), Enum.reverse(unlocked)} end)
  end

  @doc "当前可操作（available 未完成）的阶段列表"
  @spec available_stages([map()]) :: [atom()]
  def available_stages(descriptors) do
    descriptors
    |> Enum.filter(&(&1.status == :available))
    |> Enum.sort_by(& &1.order)
    |> Enum.map(& &1.stage)
  end

  @doc "流程是否全部完成（除急诊捷径外，7 阶段均 completed/skipped）"
  @spec finished?([map()]) :: boolean()
  def finished?(descriptors) do
    descriptors != [] and
      Enum.all?(descriptors, fn d -> d.status in [:completed, :skipped] end)
  end
end
