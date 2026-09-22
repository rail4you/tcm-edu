defmodule TcmEdu.SimulatedPatient.ExamplesTest do
  @moduledoc """
  `TcmEdu.SimulatedPatient.Examples` 单元测试。

  验证内置示例病人模板：

    * 至少有一个模板
    * 每个模板的必填字段齐全（name / complaint / key_points / rubric / min_questions / max_turns）
    * 每个模板的 rubric 总和为 100
    * 默认 min_questions=5 / max_turns=20
  """

  use ExUnit.Case, async: true

  alias TcmEdu.SimulatedPatient.Examples

  test "至少内置 1 个示例模板" do
    assert length(Examples.list()) >= 1
  end

  test "每个示例模板字段齐全" do
    for ex <- Examples.list() do
      assert is_binary(ex.key) and ex.key != ""
      assert is_binary(ex.label) and ex.label != ""
      t = ex.template
      assert is_binary(t.name) and t.name != ""
      assert is_binary(t.complaint) and t.complaint != ""
      assert is_list(t.key_points) and t.key_points != []
      assert is_map(t.profile) and map_size(t.profile) > 0
      assert is_map(t.rubric)
      assert t.min_questions == 5
      assert t.max_turns == 20
      assert t.difficulty in 1..5
    end
  end

  test "每个示例模板的 rubric 总和为 100" do
    for ex <- Examples.list() do
      total = ex.template.rubric |> Map.values() |> Enum.sum()
      assert total == 100, "#{ex.key}: rubric total #{total} != 100"
    end
  end

  test "get/1 取指定模板" do
    [first | _] = Examples.list()

    assert Examples.get(first.key) == first.template
    assert is_nil(Examples.get("nonexistent_key"))
  end

  test "to_form_params/1 返回可直接套到 patient_form 的形状" do
    [first | _] = Examples.list()
    params = Examples.to_form_params(first.key)

    assert is_map(params)
    assert params["name"] == first.template.name
    assert params["complaint"] == first.template.complaint
    assert is_list(params["profile_keys"])
    assert is_list(params["profile_values"])
    assert length(params["profile_keys"]) == map_size(first.template.profile)
    assert is_list(params["rubric_keys"])
    assert is_list(params["rubric_values"])
    assert length(params["rubric_keys"]) == map_size(first.template.rubric)
    # rubric key 在表单上是中文 label，存储时再翻译回英文 canonical
    assert "专业度" in params["rubric_keys"]
    assert "同理心" in params["rubric_keys"]
    assert "沟通技巧" in params["rubric_keys"]
    assert params["key_points_lines"] == first.template.key_points
    assert params["status"] == "draft"

    assert is_nil(Examples.to_form_params("nonexistent_key"))
  end
end
