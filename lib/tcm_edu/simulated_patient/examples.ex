defmodule TcmEdu.SimulatedPatient.Examples do
  @moduledoc """
  标准常见慢性病的「标准化病人」示例模板。

  教师在创建病人档案时可点击「加载示例病人」一键填表——省去手写
  主诉 / 病史 / 性格 / 评分要点的重复劳动。

  每个模板是一段纯数据，可直接套用到新建表单上。
  """

  @type template :: %{
          name: String.t(),
          subject: atom(),
          scenario_title: String.t(),
          profile: %{String.t() => String.t()},
          complaint: String.t(),
          history: String.t(),
          personality: String.t(),
          talking_style: String.t(),
          key_points: [String.t()],
          rubric: %{String.t() => integer()},
          difficulty: integer(),
          min_questions: integer(),
          max_turns: integer()
        }

  @templates [
    %{
      key: "hypertension",
      label: "原发性高血压（多年随访）",
      template: %{
        name: "王大爷",
        subject: :traditional_chinese_medicine,
        scenario_title: "头晕 1 周，加重伴头痛 2 天",
        profile: %{
          "年龄" => "65",
          "性别" => "男",
          "职业" => "退休工人"
        },
        complaint: "我这一个星期老是头晕，今天早上起来头还疼得厉害。",
        history: """
        现病史：1 周前无明显诱因出现头晕，晨起明显，伴轻度头痛，无恶心呕吐，无视物旋转，无肢体麻木。自行口服「复方降压片」症状改善不明显。今晨头痛加重，伴颈项僵硬感。
        既往史：高血压病史 12 年，长期口服硝苯地平控释片 30mg qd，血压控制不详。2 型糖尿病 5 年，二甲双胍 0.5g bid。
        体格检查：BP 168/96 mmHg，神情，精神一般，面色潮红。心肺听诊无异常。双下肢无水肿。
        """,
        personality: "焦虑、健谈、对自身病情有一定了解",
        talking_style: "句长偏长，会主动描述既往用药情况，偶尔反问医生问题",
        key_points: [
          "问头晕发作时间、持续时间、诱因",
          "问伴随症状：头痛、恶心、视物模糊、肢体麻木",
          "询问既往高血压病程、用药及血压控制情况",
          "询问糖尿病等合并症及用药",
          "询问家族高血压 / 脑卒中史",
          "询问生活方式：吸烟、饮酒、饮食盐摄入",
          "解释血压控制目标，强调规律服药",
          "安抚焦虑情绪，解释头晕多数可控"
        ],
        rubric: %{"professional" => 50, "empathy" => 25, "communication" => 25},
        difficulty: 3,
        min_questions: 5,
        max_turns: 20
      }
    },
    %{
      key: "t2dm",
      label: "2 型糖尿病（初诊乏力、多饮）",
      template: %{
        name: "李阿姨",
        subject: :traditional_chinese_medicine,
        scenario_title: "乏力伴口干多饮 1 月余",
        profile: %{
          "年龄" => "52",
          "性别" => "女",
          "职业" => "家庭主妇"
        },
        complaint: "最近一个月总觉得很累，老是想喝水，夜里还得起来喝水好几次。",
        history: """
        现病史：1 月余前无明显诱因出现乏力、口干、多饮，每日饮水量约 3-4L，尿量增多，体重 2 月内下降约 3 kg。无明显多食易饥，无心悸、手抖。
        既往史：体型偏胖，喜甜食。否认高血压、心脏病史。月经史正常，已绝经 1 年。
        体格检查：BP 132/82 mmHg，BMI 27.4 kg/m²，心肺听诊无异常，足背动脉搏动正常。
        """,
        personality: "紧张、爱追问、对糖尿病概念不清楚",
        talking_style: "短句偏多，会反复确认自己是不是得了糖尿病",
        key_points: [
          "问三多一少症状（多饮多食多尿消瘦）",
          "问乏力、体重下降时长",
          "询问既往血糖监测情况",
          "询问家族糖尿病史",
          "询问饮食习惯、运动情况",
          "解释空腹 / 餐后血糖、糖化血红蛋白意义",
          "强调生活方式干预（饮食、运动）"
        ],
        rubric: %{"professional" => 50, "empathy" => 25, "communication" => 25},
        difficulty: 2,
        min_questions: 5,
        max_turns: 20
      }
    },
    %{
      key: "chd",
      label: "稳定型心绞痛（胸痛）",
      template: %{
        name: "张师傅",
        subject: :clinical,
        scenario_title: "活动后胸闷胸痛 2 月",
        profile: %{
          "年龄" => "58",
          "性别" => "男",
          "职业" => "出租车司机"
        },
        complaint: "这 2 个月，开车时间一长胸口就闷疼，停下来歇几分钟就好。",
        history: """
        现病史：2 月前开始快走或上 3 层楼时出现胸骨后压榨样疼痛，持续 3-5 分钟，休息后可缓解。伴轻度出汗、左肩放射痛。无晕厥、黑朦。无咳嗽、咳痰。
        既往史：高血压 8 年（口服氨氯地平 5mg qd），吸烟 30 年，约 20 支/日，偶饮酒。父亲冠心病史，已行 PCI。
        体格检查：BP 146/88 mmHg，HR 76 bpm，心律齐，心肺听诊无明显异常。
        """,
        personality: "硬朗、沉默寡言、对病情有回避倾向",
        talking_style: "惜字如金，需要医生主动追问才补充细节",
        key_points: [
          "问胸痛部位、性质、持续时间、放射",
          "问诱发因素（活动、情绪）、缓解方式",
          "询问伴随症状：出汗、晕厥、呼吸困难",
          "询问既往高血压 / 高血脂 / 糖尿病",
          "询问吸烟史、家族心血管病史",
          "解释心电图 / 运动负荷试验必要性",
          "强调立即戒烟"
        ],
        rubric: %{"professional" => 50, "empathy" => 25, "communication" => 25},
        difficulty: 4,
        min_questions: 5,
        max_turns: 20
      }
    },
    %{
      key: "copd",
      label: "慢性阻塞性肺疾病（COPD）",
      template: %{
        name: "赵伯伯",
        subject: :clinical,
        scenario_title: "反复咳嗽咳痰 10 年，加重伴气短 1 周",
        profile: %{
          "年龄" => "70",
          "性别" => "男",
          "职业" => "退休矿工"
        },
        complaint: "我这咳嗽老毛病十来年了，最近一周喘得厉害，连上洗手间都费劲。",
        history: """
        现病史：慢性咳嗽、咳痰 10 余年，每年冬季加重。1 周前受凉后咳嗽咳痰加重，痰量增多、色黄黏稠，活动后明显气短。无发热、盗汗。
        既往史：吸烟 50 年，30 支/日，未戒烟。否认高血压、糖尿病。
        体格检查：桶状胸，双肺呼吸音减低，可闻及散在干啰音。
        """,
        personality: "倔强、不愿戒烟、对长期用药有抵触",
        talking_style: "语速慢、常咳嗽打断、易激动",
        key_points: [
          "问咳嗽咳痰年限、性质、痰量、痰色",
          "问呼吸困难程度、活动耐量",
          "询问吸烟史（包·年）、戒烟意愿",
          "询问既往肺功能检查、用药情况",
          "询问过敏史、职业暴露史",
          "解释长期吸入剂使用必要性",
          "强烈建议戒烟并解释 COPD 进展危害"
        ],
        rubric: %{"professional" => 50, "empathy" => 25, "communication" => 25},
        difficulty: 3,
        min_questions: 5,
        max_turns: 20
      }
    },
    %{
      key: "ckd",
      label: "慢性肾脏病（CKD 3 期）",
      template: %{
        name: "钱奶奶",
        subject: :clinical,
        scenario_title: "体检发现血肌酐升高 1 月",
        profile: %{
          "年龄" => "68",
          "性别" => "女",
          "职业" => "退休教师"
        },
        complaint: "上个月体检说我血肌酐偏高，今天来问问到底怎么回事。",
        history: """
        现病史：1 月前体检发现血肌酐 156 μmol/L，无明显水肿、尿量正常，无尿频尿急尿痛，无肉眼血尿，无腰酸腰痛。
        既往史：高血压 15 年，2 型糖尿病 8 年，长期口服降压药及二甲双胍。否认肝炎、结核病史。
        体格检查：BP 152/88 mmHg，面色无苍白，双下肢轻度凹陷性水肿。
        辅助检查：尿常规蛋白 ±，尿微量白蛋白 / 肌酐 86 mg/g。
        """,
        personality: "焦虑、爱看科普、对检查结果敏感",
        talking_style: "中等句长，会主动问「是不是要透析了」",
        key_points: [
          "问血肌酐发现经过、变化趋势",
          "询问高血压、糖尿病控制情况",
          "询问水肿、尿量、尿色、夜尿",
          "询问用药史（尤其肾毒性药物：NSAIDs、造影剂）",
          "解释 CKD 分期与 eGFR 概念",
          "解释低蛋白饮食、避免肾毒性药物",
          "安抚焦虑，明确告知多数 3 期可长期稳定"
        ],
        rubric: %{"professional" => 50, "empathy" => 25, "communication" => 25},
        difficulty: 4,
        min_questions: 5,
        max_turns: 20
      }
    }
  ]

  @doc "列出所有模板（按 label 升序）"
  @spec list() :: [%{key: String.t(), label: String.t(), template: template()}]
  def list, do: @templates

  @doc "按 key 取模板"
  @spec get(String.t()) :: template() | nil
  def get(key) do
    case Enum.find(@templates, &(&1.key == key)) do
      nil -> nil
      %{template: t} -> t
    end
  end

  @doc "把模板套到表单初始参数（用于新建病人时一键填表）"
  @spec to_form_params(String.t()) :: map() | nil
  def to_form_params(key) do
    case get(key) do
      nil ->
        nil

      t ->
        profile_lines = map_to_lines(t.profile)
        rubric_lines = map_to_lines_with_label(t.rubric)

        %{
          "name" => t.name,
          "subject" => to_string(t.subject),
          "scenario_title" => t.scenario_title,
          "complaint" => t.complaint,
          "history" => t.history,
          "personality" => t.personality,
          "talking_style" => t.talking_style,
          "key_points_lines" => t.key_points,
          "profile_keys" => Enum.map(profile_lines, &elem(&1, 0)),
          "profile_values" => Enum.map(profile_lines, &elem(&1, 1)),
          "rubric_keys" => Enum.map(rubric_lines, &elem(&1, 0)),
          "rubric_values" => Enum.map(rubric_lines, &elem(&1, 1)),
          "difficulty" => t.difficulty,
          "min_questions" => t.min_questions,
          "max_turns" => t.max_turns,
          "status" => "draft"
        }
    end
  end

  defp map_to_lines(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end

  # 把 rubric 的英文 key 翻译成中文 label 后再返回（教师端 UI 默认展示中文）
  defp map_to_lines_with_label(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      {TcmEdu.SimulatedPatient.RubricTranslations.to_label(to_string(k)), to_string(v)}
    end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end
end
