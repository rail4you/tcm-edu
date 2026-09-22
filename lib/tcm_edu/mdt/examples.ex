defmodule TcmEdu.Mdt.Examples do
  @moduledoc "MDT 会诊病例模板（mock 数据），教师一键创建。"
  alias TcmEdu.Mdt.Case

  @templates [
    %{
      key: "ami_mdt",
      label: "急诊 · 急性心肌梗死 MDT",
      name: "急性心肌梗死多学科会诊",
      scenario_title: "突发胸痛，需急诊科/心血管内科/影像科协同",
      profile: %{"年龄" => "61", "性别" => "男", "职业" => "保安"},
      complaint: "突发胸骨后压榨样疼痛 30 分钟，伴大汗、气促",
      history: "高血压 10 年、2 型糖尿病 6 年、吸烟 30 年。胸痛向左臂放射，含服硝酸甘油无效。",
      departments: ["急诊科", "心血管内科", "影像科"],
      expected_conclusion: "急性 ST 段抬高型心肌梗死，尽早再灌注（直接 PCI）"
    },
    %{
      key: "chest_uncertain_mdt",
      label: "进阶 · 胸痛待查 MDT（多科鉴别）",
      name: "胸痛待查跨科会诊",
      scenario_title: "胸痛原因不明，需内科/呼吸/影像协同排查",
      profile: %{"年龄" => "55", "性别" => "女", "职业" => "会计"},
      complaint: "间断胸痛 1 月，深呼吸时加重",
      history: "无高血压糖尿病，吸烟史 10 年。胸痛与体位/呼吸相关，偶伴干咳。",
      departments: ["心血管内科", "呼吸内科", "影像科"],
      expected_conclusion: "需同时排查心源性、胸膜/肺源性、情绪相关病因并制定检查分工"
    }
  ]

  @doc "列出全部模板"
  @spec list() :: [map()]
  def list, do: @templates

  @doc "按 key 取模板"
  @spec get(String.t()) :: map() | nil
  def get(key), do: Enum.find(@templates, &(&1.key == key))

  @doc "把模板解析成 Case 创建参数"
  @spec to_attrs(String.t(), map()) :: map() | nil
  def to_attrs(key, actor) do
    case get(key) do
      nil ->
        nil

      t ->
        %{
          name: t.name,
          scenario_title: t.scenario_title,
          profile: t.profile,
          complaint: t.complaint,
          history: t.history,
          departments: t.departments,
          expected_conclusion: t.expected_conclusion,
          status: :published,
          created_by_id: actor.id,
          created_by_email: to_string(actor.email)
        }
    end
  end

  @doc "直接创建一个已发布的 MDT 病例（幂等：同一 key 已存在则忽略）"
  @spec create!(String.t(), map(), keyword()) :: {:ok, Case.t() | nil} | {:error, term()}
  def create!(key, actor, opts) do
    tenant = opts[:tenant]

    case to_attrs(key, actor) do
      nil ->
        {:error, :not_found}

      attrs ->
        case Case.create_case(attrs, actor: actor, tenant: tenant) do
          {:ok, case} -> {:ok, case}
          {:error, error} -> {:error, Exception.message(error)}
        end
    end
  end
end