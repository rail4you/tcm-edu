defmodule TcmEdu.SimulatedPatient.ClinicalCasesTest do
  @moduledoc "`ClinicalCases` 全流程病例模板测试。"

  use ExUnit.Case, async: true

  alias TcmEdu.SimulatedPatient.{ClinicalCases, ClinicalWorkflow}

  test "包含四个难度分级至少各一个病例，且每例都带标准路径" do
    levels = ClinicalCases.list() |> Enum.map(& &1.difficulty_level)

    for level <- [:introductory, :advanced, :expert, :emergency] do
      assert level in levels, "缺少难度分级 #{level} 的病例"
    end

    for template <- ClinicalCases.list() do
      assert Map.has_key?(template.standard_pathway, :inquiry)
      assert Map.has_key?(template.standard_pathway, :follow_up)

      # 急诊必须配置 red flags
      if template.difficulty_level == :emergency do
        assert template.red_flags != [], "急诊病例 #{template.key} 必须有 red flags"
      end
    end
  end

  test "标准路径覆盖七个阶段键" do
    for template <- ClinicalCases.list() do
      for stage <- ClinicalWorkflow.stages() do
        assert Map.has_key?(template.standard_pathway, stage),
               "#{template.key} 缺阶段 #{stage}"
      end
    end
  end

  test "to_form_params 输出可直接套表单（含 standard_pathway_json / red_flags_lines / difficulty_level）" do
    params = ClinicalCases.to_form_params("emergency_ami")

    assert params["difficulty_level"] == "emergency"
    assert params["red_flags_lines"] |> length() >= 1
    assert is_binary(params["standard_pathway_json"])
    assert Jason.decode!(params["standard_pathway_json"])["diagnosis"]["primary"]
  end

  test "difficulty_levels 返回 {中文label, atom} 列表" do
    levels = ClinicalCases.difficulty_levels()
    assert Enum.any?(levels, fn {label, v} -> label == "急诊" and v == :emergency end)
  end

  test "get 不存在的 key 返回 nil" do
    assert ClinicalCases.get("nope") == nil
  end
end