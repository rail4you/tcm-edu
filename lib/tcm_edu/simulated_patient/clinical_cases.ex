defmodule TcmEdu.SimulatedPatient.ClinicalCases do
  @moduledoc """
  全流程临床模拟病例模板（mock 数据），覆盖四档难度分级。

  每个模板是一段纯数据，可直接套用到教师端「AI 模拟诊疗」的新建填表，
  并且带完整的 `standard_pathway`（七阶段标准动作清单）与 `difficulty_level`，
  供学生端触发全流程模式。

  难度分级对应：

    * `:introductory` — 入门（典型病例、线性）
    * `:advanced`     — 进阶（复杂病例、需鉴别）
    * `:expert`       — 专家（疑难杂症、多分支）
    * `:emergency`    — 急诊（危重病例、red flag 强约束）

  `to_form_params/1` 输出可直接喂给 `patient_form`（含 `standard_pathway_json`
  与 `red_flags_lines`）。
  """

  @type template :: %{
          key: String.t(),
          label: String.t(),
          difficulty_level: atom(),
          difficulty: integer(),
          standard_pathway: map(),
          red_flags: [String.t()],
          name: String.t(),
          subject: atom(),
          scenario_title: String.t(),
          profile: map(),
          complaint: String.t(),
          history: String.t(),
          personality: String.t(),
          talking_style: String.t(),
          key_points: [String.t()]
        }

  @templates [
    # ── 入门：典型病例 ────────────────────────────────────────
    %{
      key: "intro_t2dm",
      label: "入门 · 2 型糖尿病初诊（典型病例）",
      difficulty_level: :introductory,
      difficulty: 2,
      standard_pathway: %{
        inquiry: %{
          must_ask: ["三多一少症状（多饮多食多尿消瘦）", "乏力与体重下降时长", "既往血糖监测与家族史", "饮食习惯与运动"],
          min_steps: 4,
          hint: "从乏力、口渴切入，追问三多一少"
        },
        physical_exam: %{
          must_perform: ["身高体重与 BMI", "血压与心率", "足部皮肤与足背动脉"],
          signs: "BMI 27.4，血压 132/82，足背动脉搏动正常"
        },
        auxiliary: %{
          lab_orders: ["空腹血糖", "糖化血红蛋白", "尿常规"],
          imaging: [],
          hint: "空腹血糖 + 糖化即可确诊分型管理"
        },
        diagnosis: %{primary: "2 型糖尿病", evidence: ["空腹血糖 ↑", "HbA1c ↑", "无典型酮症"]},
        differential: %{
          competitors: ["1 型糖尿病", "应激性高血糖", "药物性高血糖"],
          how_to_rules_out: ["发病年龄大且无酮症倾向可除外 1 型", "追问糖皮质激素等药物史"]
        },
        treatment: %{
          plan: ["生活方式干预（饮食+运动）", "二甲双胍起始", "定期监测血糖"],
          contraindications: ["eGFR<30 慎用二甲双胍"]
        },
        follow_up: %{criteria: ["复查空腹血糖与 HbA1c", "评估低血糖与体重变化"], timeline: "2-4 周复诊"}
      },
      red_flags: [],
      name: "李阿姨",
      subject: :traditional_chinese_medicine,
      scenario_title: "乏力伴口干多饮 1 月余",
      profile: %{"年龄" => "52", "性别" => "女", "职业" => "家庭主妇"},
      complaint: "最近一个月总觉得很累，老是想喝水，夜里还得起来喝水好几次。",
      history: """
      现病史：1 月余前无明显诱因出现乏力、口干、多饮，每日饮水量约 3-4L，尿量增多，体重 2 月内下降约 3 kg。无明显多食易饥，无心悸、手抖。
      既往史：体型偏胖，喜甜食。否认高血压、心脏病史。已绝经 1 年。
      """,
      personality: "紧张、爱追问、对糖尿病概念不清楚",
      talking_style: "短句偏多，会反复确认自己是不是得了糖尿病",
      key_points: ["问三多一少症状", "问体重下降时长", "问家族糖尿病史", "解释血糖与糖化意义"]
    },

    # ── 进阶：复杂病例（需鉴别）────────────────────────────────
    %{
      key: "advanced_stable_angina",
      label: "进阶 · 稳定型心绞痛（需与夹层/肺栓塞鉴别）",
      difficulty_level: :advanced,
      difficulty: 3,
      standard_pathway: %{
        inquiry: %{
          must_ask: ["胸痛部位/性质/持续时间/放射", "诱发与缓解方式", "既往高血压/高脂/糖尿病", "吸烟与家族心血管史"],
          min_steps: 4,
          hint: "需先排查高危（撕裂样痛、呼吸困难）"
        },
        physical_exam: %{must_perform: ["生命体征", "心肺听诊", "四肢脉搏"], signs: "血压 146/88，心律齐，无杂音"},
        auxiliary: %{
          lab_orders: ["心电图", "肌钙蛋白", "心肌酶谱"],
          imaging: ["胸部 CT"],
          hint: "急诊胸痛需先心电图排除 ACS"
        },
        diagnosis: %{primary: "冠心病 稳定型心绞痛", evidence: ["活动诱发", "休息缓解", "ECG 缺血改变"]},
        differential: %{
          competitors: ["急性冠脉综合征", "主动脉夹层", "肺栓塞"],
          how_to_rules_out: ["无持续不缓解的静息痛可除外 ACS", "无撕裂样痛且双上肢血压接近可除外夹层", "无突发呼吸困难与低氧可除外肺栓塞"]
        },
        treatment: %{
          plan: ["抗血小板（阿司匹林）", "他汀调脂", "β受体阻滞剂/CCB 控制心绞痛", "硝酸甘油按需"],
          contraindications: ["活动性出血慎用抗血小板", "严重心动过缓慎用β受体阻滞剂"]
        },
        follow_up: %{criteria: ["评估胸痛发作频率与活动耐量", "复查血脂与肝酶"], timeline: "2 周复诊"}
      },
      red_flags: ["持续不缓解的压榨样胸痛", "血压骤降或双上肢压差大", "呼吸困难伴低氧"],
      name: "张师傅",
      subject: :clinical,
      scenario_title: "活动后胸闷胸痛 2 月",
      profile: %{"年龄" => "58", "性别" => "男", "职业" => "出租车司机"},
      complaint: "开车时间一长胸口就闷疼，停下来歇几分钟就好。",
      history: """
      现病史：2 月前开始快走或上 3 层楼时出现胸骨后压榨样疼痛，持续 3-5 分钟，休息后可缓解。伴轻度出汗、左肩放射痛。无晕厥、无呼吸困难。
      既往史：高血压 8 年（氨氯地平 5mg qd），吸烟 30 年 20 支/日，父亲冠心病已行 PCI。
      """,
      personality: "硬朗、沉默寡言、对病情有回避倾向",
      talking_style: "惜字如金，需要医生主动追问才补充细节",
      key_points: ["问胸痛性质/放射/诱因/缓解", "问伴随症状与既往心血管史", "解释心电图必要性", "强调戒烟"]
    },

    # ── 进阶：COPD 急性加重 ───────────────────────────────────
    %{
      key: "advanced_copd",
      label: "进阶 · COPD 急性加重（合并呼吸功能评估）",
      difficulty_level: :advanced,
      difficulty: 3,
      standard_pathway: %{
        inquiry: %{
          must_ask: ["咳嗽咳痰年限与加重情况", "痰量痰色变化", "呼吸困难程度与活动耐量", "吸烟史（包·年）与既往用药"],
          min_steps: 4,
          hint: "明确急性加重诱因（感染/用药中断）"
        },
        physical_exam: %{
          must_perform: ["生命体征与血氧饱和度", "胸廓与呼吸音", "发绀与水肿"],
          signs: "桶状胸，双肺呼吸音低，血氧 91%"
        },
        auxiliary: %{
          lab_orders: ["血氧饱和度", "血常规", "动脉血气"],
          imaging: ["胸部 X 线"],
          hint: "急性加重需动脉血气排除 II 型呼衰"
        },
        diagnosis: %{primary: "COPD 急性加重", evidence: ["痰量/痰色改变", "气短加重", "既往 COPD 史"]},
        differential: %{
          competitors: ["哮喘急性发作", "肺炎", "心力衰竭"],
          how_to_rules_out: ["可逆性差且发病晚可除外哮喘", "影像无实变可除外肺炎", "无心衰体征可除外心源性"]
        },
        treatment: %{
          plan: ["短效支气管扩张剂（SABA）", "全身糖皮质激素短程", "酌情抗生素", "氧疗目标 SpO2 88-92%"],
          contraindications: ["高浓度氧疗慎用于 II 型呼衰", "过度镇静药禁用"]
        },
        follow_up: %{criteria: ["评估呼吸困难与用药依从性", "戒烟干预", "接种流感疫苗"], timeline: "1-2 周复诊"}
      },
      red_flags: ["意识状态改变（CO₂潴留）", "动脉血气 II 型呼衰", "血氧持续 <88%"],
      name: "赵伯伯",
      subject: :clinical,
      scenario_title: "反复咳嗽咳痰 10 年，加重伴气短 1 周",
      profile: %{"年龄" => "70", "性别" => "男", "职业" => "退休矿工"},
      complaint: "我这咳嗽老毛病十来年了，最近一周喘得厉害，连上洗手间都费劲。",
      history: """
      现病史：慢性咳嗽、咳痰 10 余年，每年冬季加重。1 周前受凉后咳嗽咳痰加重，痰量增多、色黄黏稠，活动后明显气短。无发热、盗汗。
      既往史：吸烟 50 年 30 支/日，未戒烟。否认糖尿病。
      """,
      personality: "倔强、不愿戒烟、对长期用药有抵触",
      talking_style: "语速慢、常咳嗽打断、易激动",
      key_points: ["问咳嗽咳痰年限/痰量/痰色", "问呼吸困难程度与活动耐量", "问吸烟史与戒烟意愿", "解释长期吸入剂必要性"]
    },

    # ── 专家：疑难杂症 ────────────────────────────────────────
    %{
      key: "expert_subacute_endocarditis",
      label: "专家 · 亚急性感染性心内膜炎（疑难多分支）",
      difficulty_level: :expert,
      difficulty: 4,
      standard_pathway: %{
        inquiry: %{
          must_ask: ["长期发热与盗汗消瘦", "心脏杂音与心衰症状", "侵入操作史（拔牙/静脉用药）", "皮肤瘀点/Osler结节/甲床出血"],
          min_steps: 5,
          hint: "发热 + 心脏杂音 + 栓塞表现高度提示心内膜炎"
        },
        physical_exam: %{
          must_perform: ["生命体征", "心脏杂音听诊（新发/变化）", "皮肤黏膜瘀点与甲床", "脾肿大触诊"],
          signs: "新发主动脉瓣反流杂音，指端 Osler 结节，脾大"
        },
        auxiliary: %{
          lab_orders: ["血培养（治疗前 ×3 套）", "血常规与炎性指标", "肝肾功能"],
          imaging: ["经食管超声心动图（TEE）"],
          hint: "血培养必须在抗生素前采集，TEE 更敏感"
        },
        diagnosis: %{
          primary: "感染性心内膜炎",
          evidence: ["血培养阳性", "TEE 赘生物", "持续发热"],
          notes: "Duke 标准：≥2 项主要标准或 1 主要+3 次要"
        },
        differential: %{
          competitors: ["风湿热", "系统性红斑狼疮", "淋巴瘤", "结核"],
          how_to_rules_out: ["无关节游走痛与链球菌前驱史可除外风湿热", "免疫学指标与抗核抗体阴性可除外狼疮", "淋巴结活检与影像排除淋巴瘤"]
        },
        treatment: %{
          plan: ["经验性广谱抗生素（万古霉素+庆大霉素）", "根据血培养结果调整", "心衰/栓塞/赘生物大考虑外科"],
          contraindications: ["肾功能不全需调整庆大霉素剂量", "避免在未控制感染前行瓣膜成形"]
        },
        follow_up: %{criteria: ["血培养随访转阴", "复查超声评估赘生物", "抗生素疗程 4-6 周"], timeline: "住院规律随访"}
      },
      red_flags: ["新发脑卒中/外周栓塞征象", "突发心力衰竭", "赘生物增大或瓣膜穿孔"],
      name: "周先生",
      subject: :clinical,
      scenario_title: "反复发热伴盗汗 6 周",
      profile: %{"年龄" => "46", "性别" => "男", "职业" => "职员"},
      complaint: "这 6 个星期一直发烧，晚上盗汗，还越来越瘦。",
      history: """
      现病史：6 周来不规则发热，午后发热为主，伴盗汗、乏力、体重下降约 4kg。偶有手指末梢疼痛。近 2 月有拔牙史。
      既往史：风心病史，主动脉瓣轻度反流。无静脉吸毒、无糖尿病。
      """,
      personality: "理性、病程叙述清晰、希望得到明确诊断",
      talking_style: "叙述偏专业，会主动提供既往病史与操作史",
      key_points: ["问发热规律与伴随症状", "问脆弱的侵入操作史", "解释血培养与 TEE 必要性", "解释疗程与外科指征"]
    },

    # ── 急诊：危重病例 ────────────────────────────────────────
    %{
      key: "emergency_ami",
      label: "急诊 · 急性心肌梗死（先救命后诊断）",
      difficulty_level: :emergency,
      difficulty: 5,
      standard_pathway: %{
        inquiry: %{
          must_ask: ["持续压榨样胸痛与放射", "是否出汗/濒死感/呼吸困难", "胸痛持续时间是否 >20 分钟", "既往冠心病与危险因素"],
          min_steps: 3,
          hint: "先评估血流动力学，不可因问诊耽搁再灌注时间"
        },
        physical_exam: %{
          must_perform: ["生命体征与血流动力学", "心肺听诊", "四肢皮肤湿冷"],
          signs: "血压 90/60，心率 115，皮肤湿冷，双肺底湿啰音"
        },
        auxiliary: %{
          lab_orders: ["18 导联心电图", "肌钙蛋白（快速）", "血常规/电解质/凝血"],
          imaging: ["床旁超声（室壁运动）"],
          hint: "10 分钟内完成首份心电图"
        },
        diagnosis: %{
          primary: "急性 ST 段抬高型心肌梗死（Killip III）",
          evidence: ["ST 段抬高", "肌钙蛋白 ↑", "持续胸痛"]
        },
        differential: %{
          competitors: ["主动脉夹层", "肺栓塞", "张力性气胸"],
          how_to_rules_out: ["无撕裂样痛且血压不对称可初步除外夹层", "无突发呼吸困难与 D-二聚体阴性可除外肺栓塞", "呼吸音对称可除外张力性气胸"]
        },
        treatment: %{
          plan: ["阿司匹林+替格瑞洛负荷", "尽早再灌注（直接 PCI 优先）", "抗凝（普通肝素）", "必要时正性肌力药/升压"],
          contraindications: ["绝对禁忌溶栓（活动性出血）", "低血压慎用硝酸甘油"]
        },
        follow_up: %{
          criteria: ["监测心衰/心律失常", "心功能评估与康复指导", "二级预防用药（双抗+他汀+ACEI+β激阻）"],
          timeline: "PCI 后住院监测"
        }
      },
      red_flags: ["持续胸痛 >20 分钟伴大汗", "心原性休克（血压<90/心率快）", "致死性心律失常（室颤）", "Killip 分级恶化"],
      name: "孙先生",
      subject: :clinical,
      scenario_title: "突发胸骨后压榨样疼痛 30 分钟",
      profile: %{"年龄" => "61", "性别" => "男", "职业" => "保安"},
      complaint: "胸口突然像被石头压住一样疼，疼了大半个小时，出冷汗，喘不上气。",
      history: """
      现病史：30 分钟前活动后突发胸骨后压榨样疼痛，向左臂放射，伴大汗、濒死感、气促。自行含着硝酸甘油无效。
      既往史：2 型糖尿病 6 年、高血压 10 年、长期吸烟。否认胃溃疡、出血史。
      """,
      personality: "疼痛难忍、急躁、表达不清",
      talking_style: "语速快、喘、会催促医生快点处理",
      key_points: ["先评估生命体征与再灌注时间", "10 分钟内做心电图", "识别心原性休克与心律失常", "明确再灌注策略与时间窗"]
    },

    # ── 急诊：过敏性休克 ──────────────────────────────────────
    %{
      key: "emergency_anaphylaxis",
      label: "急诊 · 过敏性休克（药物过敏）",
      difficulty_level: :emergency,
      difficulty: 5,
      standard_pathway: %{
        inquiry: %{
          must_ask: ["过敏原暴露（药物/食物/虫咬）与时间", "皮疹/喉头水肿/呼吸困难", "既往过敏史与哮喘史"],
          min_steps: 3,
          hint: "血压下降+气道症状高度提示休克，先用药再问诊"
        },
        physical_exam: %{
          must_perform: ["气道与呼吸评估", "皮肤（荨麻疹/血管性水肿）", "血压心率血氧"],
          signs: "血压 70/40，心率 130，全身荨麻疹，喉鸣音"
        },
        auxiliary: %{lab_orders: ["血常规", "血气", "必要时组胺/类胰蛋白酶"], imaging: [], hint: "救治优先，检查不做延误"},
        diagnosis: %{primary: "过敏性休克（Ⅱ级）", evidence: ["血压骤降", "荨麻疹+血管性水肿", "明确过敏原暴露"]},
        differential: %{
          competitors: ["心源性休克", "迷走反射", "低血糖"],
          how_to_rules_out: ["无心梗证据且无胸痛可初步除外心源性", "无苍白冷汗前驱且无张力可除外迷走反射"]
        },
        treatment: %{
          plan: ["立即停止过敏原", "肾上腺素 0.3-0.5mg IM 首选", "大量晶体液扩容", "抗组胺+糖皮质激素辅助", "严重喉水肿考虑气管插管"],
          contraindications: ["肾上腺素禁止仅皮下注射", "禁用β受体阻滞剂加重难治性休克"]
        },
        follow_up: %{
          criteria: ["观察 24h 防双相反应", "开具过敏原警示与肾上腺素自动注射装置", "转诊过敏专科"],
          timeline: "留观 24h"
        }
      },
      red_flags: ["气道阻塞（喉头水肿/喉鸣）", "血压持续 <90/60 休克", "双相反应风险", "对肾上腺素无反应"],
      name: "陈女士",
      subject: :clinical,
      scenario_title: "输液后突发面色苍白、喘憋 5 分钟",
      profile: %{"年龄" => "34", "性别" => "女", "职业" => "文员"},
      complaint: "刚打完一瓶药没多久，突然又痒又喘，眼前发黑，快不行了的感觉。",
      history: """
      现病史：静脉输液（可疑头孢类）约 10 分钟后出现全身荨麻疹、瘙痒、呼吸困难、头晕、心悸，随后意识模糊感。
      既往史：青霉素过敏史，哮喘史。否认糖尿病。
      """,
      personality: "极度恐慌、气促、难以完整作答",
      talking_style: "断断续续、喘促、间隔停顿",
      key_points: ["立即停过敏原并评估气道", "第一时间 IM 肾上腺素", "大量补液纠正休克", "识别并处理双相反应"]
    }
  ]

  @doc "列出所有模板"
  @spec list() :: [%{key: String.t(), label: String.t(), template: template()}]
  def list, do: @templates

  @doc "按 key 取模板"
  @spec get(String.t()) :: template() | nil
  def get(key) do
    case Enum.find(@templates, &(&1.key == key)) do
      nil -> nil
      t -> t
    end
  end

  @doc "难度分级常见（供 UI 下拉）"
  @spec difficulty_levels() :: [{String.t(), atom()}]
  def difficulty_levels do
    TcmEdu.SimulatedPatient.ClinicalWorkflow.difficulty_levels()
    |> Enum.map(&{TcmEdu.SimulatedPatient.ClinicalWorkflow.difficulty_label(&1), &1})
  end

  @doc "把模板套到表单初始参数（含 standard_pathway_json 与 red_flags_lines）"
  @spec to_form_params(String.t()) :: map() | nil
  def to_form_params(key) do
    case get(key) do
      nil ->
        nil

      t ->
        profile_lines = map_to_lines(t.profile)

        rubric_lines =
          map_to_lines_with_label(%{"professional" => 50, "empathy" => 25, "communication" => 25})

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
          "difficulty_level" => to_string(t.difficulty_level),
          "standard_pathway_json" => Jason.encode!(t.standard_pathway),
          "red_flags_lines" => t.red_flags,
          "min_questions" => 3,
          "max_turns" => 30,
          "status" => "draft"
        }
    end
  end

  defp map_to_lines(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end

  # 把 rubric 的英文 key 翻译成中文 label 后再返回
  defp map_to_lines_with_label(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      {TcmEdu.SimulatedPatient.RubricTranslations.to_label(to_string(k)), to_string(v)}
    end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end
end
