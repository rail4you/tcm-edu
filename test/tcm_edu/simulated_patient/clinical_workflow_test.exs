defmodule TcmEdu.SimulatedPatient.ClinicalWorkflowTest do
  @moduledoc "`ClinicalWorkflow` 阶段定义与难度分级配置测试。"

  use ExUnit.Case, async: true

  alias TcmEdu.SimulatedPatient.ClinicalWorkflow

  test "stages 按 问诊→随访 顺序" do
    assert ClinicalWorkflow.stages() == [
             :inquiry,
             :physical_exam,
             :auxiliary,
             :diagnosis,
             :differential,
             :treatment,
             :follow_up
           ]
  end

  test "标签与顺序号" do
    assert ClinicalWorkflow.label(:physical_exam) == "体格检查"
    assert ClinicalWorkflow.order_of(:inquiry) == 1
    assert ClinicalWorkflow.order_of(:follow_up) == 7
    assert ClinicalWorkflow.stage_at(4) == :diagnosis
  end

  test "难度配置" do
    assert ClinicalWorkflow.difficulty_label(:emergency) == "急诊"
    assert ClinicalWorkflow.elastic_order?(:emergency)
    assert ClinicalWorkflow.elastic_order?(:expert)
    refute ClinicalWorkflow.elastic_order?(:introductory)
    assert ClinicalWorkflow.red_flag_strict?(:emergency)
    refute ClinicalWorkflow.red_flag_strict?(:introductory)
  end

  test "build_stage_descriptors：入门线性解锁（仅第一段可用）" do
    descriptors =
      ClinicalWorkflow.build_stage_descriptors(%{
        difficulty_level: :introductory
      })

    assert length(descriptors) == 7
    assert Enum.map(descriptors, & &1.stage) == ClinicalWorkflow.stages()

    statuses = Enum.map(descriptors, & &1.status)
    assert statuses == [:available, :locked, :locked, :locked, :locked, :locked, :locked]
  end

  test "build_stage_descriptors：急诊全部可操作（先救命）" do
    descriptors =
      ClinicalWorkflow.build_stage_descriptors(%{
        difficulty_level: :emergency
      })

    assert Enum.all?(descriptors, &(&1.status == :available))
  end

  test "build_stage_descriptors：专家问诊+查体同时可操作" do
    descriptors =
      ClinicalWorkflow.build_stage_descriptors(%{
        difficulty_level: :expert
      })

    assert Enum.map(descriptors, & &1.status) ==
             [:available, :available, :locked, :locked, :locked, :locked, :locked]
  end

  test "difficulty_range 映射" do
    assert ClinicalWorkflow.difficulty_range(:introductory) == 1..2
    assert ClinicalWorkflow.difficulty_range(:emergency) == 5..5
  end
end