defmodule TcmEdu.SimulatedPatient.RubricTranslationsTest do
  @moduledoc """
  `TcmEdu.SimulatedPatient.RubricTranslations` 单元测试。

  验证：

    * 默认三条维度按英文 canonical key（professional / empathy / communication）返回
    * UI 默认行用中文 label 展示
    * `normalize_key/1` 把中文标签翻成英文 canonical key
    * `to_label/1` 把英文 canonical key 翻成中文 label
    * 未知 key 原样返回（允许用户自定义）
  """

  use ExUnit.Case, async: true

  alias TcmEdu.SimulatedPatient.RubricTranslations

  test "defaults/0 返回英文 canonical key" do
    assert RubricTranslations.defaults() == [
             {"professional", 50},
             {"empathy", 25},
             {"communication", 25}
           ]
  end

  test "default_label_rows/0 返回中文 label" do
    rows = RubricTranslations.default_label_rows()
    assert Enum.map(rows, & &1["k"]) == ["专业度", "同理心", "沟通技巧"]
    assert Enum.map(rows, & &1["v"]) == ["50", "25", "25"]
  end

  test "normalize_key/1 把中文翻成英文 canonical key" do
    assert RubricTranslations.normalize_key("专业度") == "professional"
    assert RubricTranslations.normalize_key("同理心") == "empathy"
    assert RubricTranslations.normalize_key("沟通技巧") == "communication"
    assert RubricTranslations.normalize_key("沟通") == "communication"
    assert RubricTranslations.normalize_key("共情") == "empathy"
  end

  test "normalize_key/1 保留英文 canonical key" do
    assert RubricTranslations.normalize_key("professional") == "professional"
    assert RubricTranslations.normalize_key("Empathy") == "empathy"
  end

  test "normalize_key/1 接受自定义 key（trim + downcase + space→_）" do
    assert RubricTranslations.normalize_key("My Dim") == "my_dim"
    assert RubricTranslations.normalize_key("  ") == ""
  end

  test "to_label/1 把英文 canonical key 翻成中文 label" do
    assert RubricTranslations.to_label("professional") == "专业度"
    assert RubricTranslations.to_label("empathy") == "同理心"
    assert RubricTranslations.to_label("communication") == "沟通技巧"
  end

  test "to_label/1 对未知 key 原样返回" do
    assert RubricTranslations.to_label("custom_dim") == "custom_dim"
    assert RubricTranslations.to_label("") == ""
  end
end
