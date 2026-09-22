defmodule TcmEdu.SimulatedPatient.RubricTranslations do
  @moduledoc """
  评分维度 key 的中英对照。

  教师端 UI 上默认展示中文标签（专业度 / 同理心 / 沟通技巧），
  但内部仍以英文 canonical key（professional / empathy / communication）存储。
  这样 LLM 评分 prompt、聚合计算逻辑与历史数据保持兼容。

  教师也可以输入任意自定义 key；本模块只负责「默认三条」的双向翻译。
  """

  # 中文 label → 英文 canonical key
  @zh_to_en %{
    "专业度" => "professional",
    "专业" => "professional",
    "同理心" => "empathy",
    "同理" => "empathy",
    "共情" => "empathy",
    "沟通技巧" => "communication",
    "沟通" => "communication",
    "交流" => "communication"
  }

  # 英文 canonical key → 中文 label（用于 UI 默认展示）
  @en_to_zh %{
    "professional" => "专业度",
    "empathy" => "同理心",
    "communication" => "沟通技巧"
  }

  @doc "把 UI 输入的 key 翻成 canonical 英文 key；非中文则原样返回（小写）"
  @spec normalize_key(String.t()) :: String.t()
  def normalize_key(key) when is_binary(key) do
    trimmed = String.trim(key)

    cond do
      trimmed == "" ->
        ""

      Map.has_key?(@zh_to_en, trimmed) ->
        Map.fetch!(@zh_to_en, trimmed)

      true ->
        # 允许用户自定义 key（英文 / 中文混输 / 缩写），统一 trim + downcase
        trimmed |> String.downcase() |> String.replace(~r/\s+/, "_")
    end
  end

  @doc "把存储的 canonical key 翻译成中文 label；未知 key 原样返回"
  @spec to_label(String.t()) :: String.t()
  def to_label(key) when is_binary(key) do
    Map.get(@en_to_zh, String.trim(key), key)
  end

  @doc "默认三条维度（key 为英文 canonical，value 默认为 50/25/25）"
  @spec defaults() :: [{String.t(), integer()}]
  def defaults do
    [
      {"professional", 50},
      {"empathy", 25},
      {"communication", 25}
    ]
  end

  @doc "默认三条维度，UI 友好版本（key 显示为中文 label）"
  @spec default_label_rows() :: [%{String.t() => String.t()}]
  def default_label_rows do
    Enum.map(defaults(), fn {key, weight} ->
      %{"k" => to_label(key), "v" => Integer.to_string(weight)}
    end)
  end
end
