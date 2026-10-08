defmodule TcmMobile.Data.Questions do
  @moduledoc """
  题库 —— 课时随堂测验与阶段测验共用。

  `type`：
  * `:single` 单选 —— `answer` 为选项下标，测验自动判分
  * `:fill`   填空 —— `answer` 为参考答案，测验只展示参考答案
  * `:essay`  问答 —— `answer` 为参考答案，测验只展示参考答案

  填空/问答在「测验」里不计分；「考试」整卷交由人工评阅。
  """

  def all do
    [
      %{
        id: "q1",
        type: :single,
        text: "五行相生的顺序是？",
        options: ["木→火→土→金→水", "木→土→火→金→水", "水→火→木→金→土", "金→水→木→火→土"],
        answer: 0,
        explanation: "五行相生：木生火、火生土、土生金、金生水、水生木。"
      },
      %{
        id: "q2",
        type: :single,
        text: "下列哪一项属于阴的属性？",
        options: ["温煦", "向上", "静止", "明亮"],
        answer: 2,
        explanation: "阴主静、主内、主寒、主降；阳主动、主外、主热、主升。"
      },
      %{
        id: "q3",
        type: :single,
        text: "「藏象」一词首见于哪部经典？",
        options: ["《伤寒论》", "《难经》", "《素问·六节藏象论》", "《神农本草经》"],
        answer: 2,
        explanation: "“藏象”首见于《素问·六节藏象论》。"
      },
      %{
        id: "q4",
        type: :single,
        text: "舌淡白多见于？",
        options: ["热证", "气血两虚或阳虚", "里热亢盛", "血瘀"],
        answer: 1,
        explanation: "舌淡白主虚寒证，多因气血两虚、血不荣舌，或阳虚水湿内停。"
      },
      %{
        id: "q5",
        type: :single,
        text: "「十问歌」中「一问寒热二问汗」出自哪位医家？",
        options: ["张仲景", "张景岳", "李时珍", "华佗"],
        answer: 1,
        explanation: "明代张景岳总结问诊「十问歌」，为问诊纲要。"
      },
      %{
        id: "q6",
        type: :single,
        text: "表证的主要特征是？",
        options: ["但热不寒", "恶寒发热并见", "但寒不热", "往来寒热"],
        answer: 1,
        explanation: "表证以恶寒（或恶风）与发热并见、脉浮为特征。"
      },
      %{
        id: "q7",
        type: :single,
        text: "下列哪味药属于辛温解表药？",
        options: ["薄荷", "牛蒡子", "桂枝", "桑叶"],
        answer: 2,
        explanation: "桂枝辛甘温，属辛温解表药；薄荷、牛蒡子、桑叶均属辛凉解表药。"
      },
      %{
        id: "q8",
        type: :single,
        text: "麻黄除发汗解表外，还具有的功效是？",
        options: ["疏肝行气", "宣肺平喘、利水消肿", "温经通脉", "清利头目"],
        answer: 1,
        explanation: "麻黄发汗解表、宣肺平喘、利水消肿，为辛温解表之峻品。"
      },
      %{
        id: "q9",
        type: :single,
        text: "方剂中针对主病主证起主要治疗作用的药物是？",
        options: ["臣药", "佐药", "使药", "君药"],
        answer: 3,
        explanation: "君药针对主病主证，起主要治疗作用，是方中不可缺少的部分。"
      },
      %{
        id: "q10",
        type: :single,
        text: "桂枝汤的治法为？",
        options: ["清热泻火", "解肌发表、调和营卫", "温中散寒", "滋阴降火"],
        answer: 1,
        explanation: "桂枝汤解肌发表、调和营卫，主治太阳中风之营卫不和。"
      },
      %{
        id: "q11",
        type: :single,
        text: "感冒风寒证的代表方是？",
        options: ["银翘散", "荆防败毒散", "桑菊饮", "麻杏石甘汤"],
        answer: 1,
        explanation: "风寒感冒用荆防败毒散疏风散寒；风热感冒用银翘散辛凉解表。"
      },
      %{
        id: "q12",
        type: :single,
        text: "风寒感冒与风热感冒的关键鉴别点是？",
        options: ["有无咳嗽", "恶寒与发热孰轻孰重", "有无流涕", "病程长短"],
        answer: 1,
        explanation: "风寒恶寒重发热轻；风热发热重恶寒轻，此为关键鉴别点。"
      },
      %{
        id: "q13",
        type: :single,
        text: "毫针刺入皮下后，医者指下出现的沉紧感，患者出现酸麻胀重感称为？",
        options: ["滞针", "得气", "晕针", "弯针"],
        answer: 1,
        explanation: "得气是针刺产生疗效的基础，表现为医者指下沉紧、患者局部酸麻胀重。"
      },
      %{
        id: "q14",
        type: :single,
        text: "孕妇禁针的穴位不包括？",
        options: ["合谷", "三阴交", "足三里", "肩井"],
        answer: 2,
        explanation: "孕妇禁针合谷、三阴交、肩井及腹部、腰骶部腧穴；足三里并非禁忌。"
      },
      %{
        id: "q15",
        type: :single,
        text: "颈椎病针灸治疗中，属远道取穴的是？",
        options: ["颈夹脊", "风池", "后溪", "天柱"],
        answer: 2,
        explanation: "后溪为手太阳经穴，通督脉，为颈椎病的远道效穴。"
      },
      %{
        id: "q16",
        type: :single,
        text: "偏头痛多从何经论治？",
        options: ["阳明经", "少阳经", "太阳经", "厥阴经"],
        answer: 1,
        explanation: "偏头痛痛在头之两侧，属少阳经循行部位，多取外关、足临泣等少阳经穴。"
      },
      %{
        id: "q17",
        type: :single,
        text: "患者咳嗽痰白清稀、畏寒肢冷、舌淡苔白，多属？",
        options: ["风热犯肺", "风寒束肺", "阴虚燥咳", "痰热壅肺"],
        answer: 1,
        explanation: "痰白清稀、畏寒、舌淡苔白为风寒束肺之象。"
      },
      %{
        id: "q18",
        type: :single,
        text: "「圣人不治已病治未病」出自？",
        options: ["《素问·四气调神大论》", "《伤寒论》", "《千金方》", "《本草纲目》"],
        answer: 0,
        explanation: "治未病思想首见于《素问·四气调神大论》。"
      },
      %{
        id: "q19",
        type: :fill,
        text: "五行相生的顺序：木 → ____ → 土 → 金 → 水。",
        options: [],
        answer: "火",
        explanation: "五行相生：木生火、火生土、土生金、金生水、水生木。"
      },
      %{
        id: "q20",
        type: :fill,
        text: "六淫之中，____ 为「百病之长」，其性善行而数变。",
        options: [],
        answer: "风",
        explanation: "风为百病之长，其性轻扬开泄、善行而数变，易兼他邪。"
      },
      %{
        id: "q21",
        type: :fill,
        text: "「治未病」的思想首见于《 ____ 》。",
        options: [],
        answer: "素问·四气调神大论",
        explanation: "《素问·四气调神大论》：「圣人不治已病治未病，不治已乱治未乱。」"
      },
      %{
        id: "q22",
        type: :fill,
        text: "针刺得气时，医者指下出现 ____ 感，患者则有酸、麻、胀、重感。",
        options: [],
        answer: "沉紧",
        explanation: "得气又称「气至」，医者指下沉紧，患者局部酸麻胀重。"
      },
      %{
        id: "q23",
        type: :essay,
        text: "简述何谓「辨证论治」，并说明其临床意义。",
        options: [],
        answer: "辨证论治是中医学认识疾病和治疗疾病的基本原则：将四诊搜集的资料加以分析综合，判断为某种性质的「证」，再据证确立治法、选方用药。同病异治、异病同治皆源于此。",
        explanation: "关键词：四诊合参 → 辨析证候 → 确立治法 → 随证治之；体现「证同治同、证异治异」。"
      },
      %{
        id: "q24",
        type: :essay,
        text: "简述寒证与热证的鉴别要点。",
        options: [],
        answer:
          "可从寒热、口渴、面色、四肢、二便、舌脉等方面鉴别：寒证恶寒喜温、口不渴、面色白、四肢冷、便溏、舌淡苔白、脉迟；热证恶热喜冷、口渴、面红、四肢温、便秘、舌红苔黄、脉数。",
        explanation: "寒热真假是难点，须四诊合参，尤重舌象与脉象。"
      },
      %{
        id: "q25",
        type: :essay,
        text: "简述风寒感冒与风热感冒的治法与代表方。",
        options: [],
        answer: "风寒感冒：辛温解表，代表方荆防败毒散；风热感冒：辛凉解表，代表方银翘散或桑菊饮。",
        explanation: "另需随证加减：夹湿宜芳香化湿，气虚宜益气解表。"
      },
      %{
        id: "q26",
        type: :essay,
        text: "何谓方剂中的「君臣佐使」？请各举一例说明其作用。",
        options: [],
        answer:
          "君药针对主病主证起主要治疗作用；臣药辅助君药或兼治次证；佐药包括佐制（制约毒性）、佐助（助君臣之力）与反佐；使药引经或调和诸药。如麻黄汤中麻黄为君、桂枝为臣、杏仁为佐、甘草为使。",
        explanation: "君臣佐使是方剂配伍的基本结构，见于《素问·至真要大论》。"
      }
    ]
  end

  def get(id), do: Enum.find(all(), &(&1.id == id))

  @doc "按 id 顺序取出题目，保持题库中定义顺序。"
  def pick(ids), do: Enum.map(ids, &get/1)

  @doc "题型 —— 老数据缺省视为单选。"
  def type(question), do: Map.get(question, :type, :single)

  @doc "是否已作答：单选看选项下标，填空 / 问答看非空文本。"
  def answered?(question, value) do
    case type(question) do
      :single -> is_integer(value)
      _ -> is_binary(value) and String.trim(value) != ""
    end
  end
end
