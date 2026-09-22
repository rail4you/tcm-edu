defmodule TcmEdu.SimulatedPatient.StageMachineTest do
  @moduledoc "`StageMachine` 阶段解锁逻辑测试。"

  use ExUnit.Case, async: true

  alias TcmEdu.SimulatedPatient.ClinicalWorkflow
  alias TcmEdu.SimulatedPatient.StageMachine

  defp descriptors(level) do
    ClinicalWorkflow.build_stage_descriptors(%{difficulty_level: level})
  end

  test "入门：完成问诊解锁查体" do
    {new, unlocked} = StageMachine.apply_completion(descriptors(:introductory), :inquiry, :introductory)

    assert unlocked == [:physical_exam]
    assert stage_status(new, :inquiry) == :completed
    assert stage_status(new, :physical_exam) == :available
    assert stage_status(new, :auxiliary) == :locked
  end

  test "入门：全部完成后 finished?" do
    d = descriptors(:introductory)

    d =
      Enum.reduce(ClinicalWorkflow.stages(), d, fn stage, acc ->
        {new, _} = StageMachine.apply_completion(acc, stage, :introductory)
        new
      end)

    assert StageMachine.finished?(d)
    assert StageMachine.available_stages(d) == []
  end

  test "专家：完成问诊后查体保持可用，完成查体后才解锁辅助检查" do
    {new, unlocked} = StageMachine.apply_completion(descriptors(:expert), :inquiry, :expert)

    assert unlocked == []
    assert stage_status(new, :inquiry) == :completed
    assert stage_status(new, :physical_exam) == :available
    assert stage_status(new, :auxiliary) == :locked

    {new2, unlocked2} = StageMachine.apply_completion(new, :physical_exam, :expert)

    assert unlocked2 == [:auxiliary]
    assert stage_status(new2, :auxiliary) == :available
    assert stage_status(new2, :diagnosis) == :locked
  end

  test "急诊：初始全部 available，完成后保持 completed" do
    d = descriptors(:emergency)
    assert StageMachine.available_stages(d) == ClinicalWorkflow.stages()

    {new, unlocked} = StageMachine.apply_completion(d, :physical_exam, :emergency)
    assert unlocked == []
    assert stage_status(new, :physical_exam) == :completed
    assert StageMachine.available_stages(new) |> length() == 6
  end

  defp stage_status(descriptors, stage) do
    Enum.find(descriptors, &(&1.stage == stage)).status
  end
end