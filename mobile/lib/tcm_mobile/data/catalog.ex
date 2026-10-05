defmodule TcmMobile.Data.Catalog do
  @moduledoc """
  学员端本地数据目录 —— 与后端 `tcm_edu` 种子课程一致的示例数据。

  离线优先：移动端自带一套贴近真实教学场景的数据（课程、课时、测验、
  模拟患者、MDT、通知、资料），由 `TcmMobile.Api` 统一暴露给界面。
  后端补上 JSON API 后，把 `TcmMobile.Api` 的数据源切到 `:remote` 即可，
  界面层不需要改动。
  """

  alias TcmMobile.Data.Questions

  # ── 教师 ────────────────────────────────────────────────────────────────────

  def teachers do
    [
      %{id: "t1", name: "张守正", title: "主任医师 · 中医内科", specialty: "肺系病证"},
      %{id: "t2", name: "李佩兰", title: "教授 · 方剂学", specialty: "经方运用"},
      %{id: "t3", name: "王鹤龄", title: "副主任医师 · 针灸推拿", specialty: "颈肩腰腿痛"},
      %{id: "t4", name: "陈杏林", title: "副教授 · 中药学", specialty: "有毒中药安全"}
    ]
  end

  def teacher(id), do: Enum.find(teachers(), &(&1.id == id))

  # ── 课程分类 ────────────────────────────────────────────────────────────────

  def categories do
    [
      %{id: "basics", name: "中医基础", icon: "book"},
      %{id: "materia-medica", name: "中药学", icon: "pills"},
      %{id: "formulas", name: "方剂学", icon: "list"},
      %{id: "acupuncture-tuina", name: "针灸推拿", icon: "bolt"},
      %{id: "clinical", name: "中医临床", icon: "heart"}
    ]
  end

  def category(id), do: Enum.find(categories(), &(&1.id == id))

  # ── 课程 ────────────────────────────────────────────────────────────────────

  def courses do
    Enum.map(base_courses(), fn c -> Map.put(c, :lesson_count, length(lessons(c.id))) end)
  end

  defp base_courses do
    [
      %{
        id: "c1",
        title: "中医基础理论精讲",
        subtitle: "阴阳五行入门",
        category: "basics",
        level: :beginner,
        teacher_id: "t1",
        description: "从阴阳五行到藏象学说，搭建中医理论的第一块基石。",
        tags: ["阴阳", "五行", "藏象"],
        student_count: 1284,
        price_cents: 0
      },
      %{
        id: "c2",
        title: "中医诊断学",
        subtitle: "望闻问切四诊合参",
        category: "basics",
        level: :beginner,
        teacher_id: "t1",
        description: "系统学习望、闻、问、切四诊方法与辨证思路。",
        tags: ["四诊", "八纲", "辨证"],
        student_count: 963,
        price_cents: 0
      },
      %{
        id: "c3",
        title: "中药学入门",
        subtitle: "四气五味升降浮沉",
        category: "materia-medica",
        level: :beginner,
        teacher_id: "t4",
        description: "认识中药的四气五味、升降浮沉与归经，掌握用药基本规律。",
        tags: ["四气", "五味", "归经"],
        student_count: 1520,
        price_cents: 0
      },
      %{
        id: "c4",
        title: "解表药与清热药",
        subtitle: "辛凉解表 · 苦寒清热",
        category: "materia-medica",
        level: :intermediate,
        teacher_id: "t4",
        description: "聚焦临床最常用的解表药与清热药，辨析相似药物的异同。",
        tags: ["解表药", "清热药"],
        student_count: 671,
        price_cents: 0
      },
      %{
        id: "c5",
        title: "方剂学基础",
        subtitle: "君臣佐使组方原则",
        category: "formulas",
        level: :beginner,
        teacher_id: "t2",
        description: "理解君臣佐使的组方结构与常用剂型，为临床组方打基础。",
        tags: ["君臣佐使", "剂型"],
        student_count: 1089,
        price_cents: 0
      },
      %{
        id: "c6",
        title: "经方十讲·桂枝汤类方",
        subtitle: "仲景群方之魁",
        category: "formulas",
        level: :intermediate,
        teacher_id: "t2",
        description: "以桂枝汤为纲，串讲其类方加减变化与临床应用。",
        tags: ["桂枝汤", "类方", "伤寒论"],
        student_count: 742,
        price_cents: 0
      },
      %{
        id: "c7",
        title: "针灸学入门",
        subtitle: "毫针刺法与得气",
        category: "acupuncture-tuina",
        level: :beginner,
        teacher_id: "t3",
        description: "毫针操作、得气与补泻手法入门，含常用腧穴定位。",
        tags: ["毫针", "腧穴", "得气"],
        student_count: 856,
        price_cents: 0
      },
      %{
        id: "c8",
        title: "头颈肩痛针灸治疗",
        subtitle: "颈椎病 · 落枕 · 偏头痛",
        category: "acupuncture-tuina",
        level: :intermediate,
        teacher_id: "t3",
        description: "针对头颈肩痛的辨证取穴思路与操作要点。",
        tags: ["颈椎病", "取穴", "头痛"],
        student_count: 598,
        price_cents: 0
      },
      %{
        id: "c9",
        title: "中医内科·肺系病证",
        subtitle: "感冒 · 咳嗽 · 哮病辨治",
        category: "clinical",
        level: :intermediate,
        teacher_id: "t1",
        description: "以肺系常见病为纲，训练四诊合参与辨证论治的完整过程。",
        tags: ["感冒", "咳嗽", "哮病"],
        student_count: 1105,
        price_cents: 0
      },
      %{
        id: "c10",
        title: "中医治未病与养生",
        subtitle: "四季养生与食疗",
        category: "clinical",
        level: :beginner,
        teacher_id: "t2",
        description: "中医治未病思想与四季养生的实用方法。",
        tags: ["治未病", "食疗", "养生"],
        student_count: 2031,
        price_cents: 0
      }
    ]
  end

  def course(id), do: Enum.find(courses(), &(&1.id == id))

  def popular_courses, do: Enum.take(Enum.sort_by(courses(), & &1.student_count, :desc), 6)

  def courses_by_category(cat_id), do: Enum.filter(courses(), &(&1.category == cat_id))

  def search_courses(query) do
    q = String.downcase(query)

    Enum.filter(courses(), fn c ->
      String.contains?(String.downcase(c.title), q) or
        String.contains?(String.downcase(c.subtitle), q) or
        Enum.any?(c.tags, &String.contains?(String.downcase(&1), q))
    end)
  end

  # ── 课时 ────────────────────────────────────────────────────────────────────

  def lessons(course_id) do
    case lessons_by_course()[course_id] do
      nil ->
        []

      {{chapter_no, _start}, specs} ->
        specs
        |> Enum.with_index()
        |> Enum.map(fn {{title, kind, duration_min}, i} ->
          %{
            id: "#{course_id}-l#{i}",
            course_id: course_id,
            chapter_no: chapter_no,
            no: i + 1,
            title: title,
            kind: kind,
            duration_min: duration_min
          }
        end)
    end
  end

  # `{chapter_no, no_offset}` per course, then lesson specs with `{title, kind, dur}`
  defp lessons_by_course do
    %{
      "c1" =>
        {{1, 1},
         [
           {"导论：阴阳学说的基本内容", :text, 18},
           {"五行生克与脏腑归属", :text, 22},
           {"藏象学说概述", :quiz, 15}
         ]},
      "c2" =>
        {{1, 1},
         [
           {"望诊：神色形态", :text, 20},
           {"问诊：十问歌与主诉采集", :text, 24},
           {"八纲辨证总纲", :quiz, 18}
         ]},
      "c3" =>
        {{1, 1},
         [
           {"四气五味与升降浮沉", :text, 20},
           {"中药的归经与配伍", :text, 16},
           {"常用解表药辨识", :quiz, 15}
         ]},
      "c4" =>
        {{1, 1},
         [
           {"辛温解表药：麻黄、桂枝、羌活", :text, 25},
           {"辛凉解表药：薄荷、牛蒡子、桑叶", :text, 22},
           {"清热药分类与对比", :quiz, 20}
         ]},
      "c5" =>
        {{1, 1},
         [
           {"君臣佐使：组方结构", :text, 21},
           {"常用剂型与煎服法", :text, 14},
           {"组方原则随堂测验", :quiz, 16}
         ]},
      "c6" =>
        {{1, 1},
         [
           {"桂枝汤方解：调和营卫", :text, 26},
           {"桂枝汤类方：桂枝加厚朴杏子汤", :text, 23},
           {"经方辨证要点测验", :quiz, 19}
         ]},
      "c7" =>
        {{1, 1},
         [
           {"毫针基本操作与进针法", :text, 24},
           {"得气与行针手法", :text, 20},
           {"针刺操作安全要点", :quiz, 17}
         ]},
      "c8" =>
        {{1, 1},
         [
           {"颈椎病的辨证取穴", :text, 26},
           {"落枕与偏头痛的针灸思路", :text, 21},
           {"取穴辨证随堂测验", :quiz, 18}
         ]},
      "c9" =>
        {{1, 1},
         [
           {"感冒证治：风寒与风热", :text, 25},
           {"咳嗽的辨证论治", :text, 24},
           {"肺系辨证测验", :quiz, 20}
         ]},
      "c10" =>
        {{1, 1},
         [
           {"治未病：未病先防与既病防变", :text, 16},
           {"四季养生要旨", :text, 18},
           {"食疗常用配伍", :text, 14}
         ]}
    }
  end

  def lesson(course_id, lesson_id) do
    lessons(course_id) |> Enum.find(&(&1.id == lesson_id))
  end

  @doc "课时正文（模拟真实教学内容）"
  def lesson_content(lesson_id) do
    body = lesson_bodies()[lesson_id] || lesson_bodies()[:default]

    body
  end

  defp lesson_bodies do
    %{
      "c1-l0" => [
        "阴阳学说认为，宇宙万物都包含着阴和阳两个对立统一的方面。",
        "《素问·阴阳应象大论》说：“阴阳者，天地之道也，万物之纲纪，变化之父母，生杀之本始。”",
        "阴阳的基本属性包括对立制约、互根互用、消长平衡与相互转化。",
        "临床上，阴阳失调是疾病发生的根本病机，故《内经》强调“善诊者，察色按脉，先别阴阳”。"
      ],
      "c1-l1" => [
        "五行即木、火、土、金、水五种基本物质的运动变化。",
        "五行相生：木生火、火生土、土生金、金生水、水生木。",
        "五行相克：木克土、土克水、水克火、火克金、金克木。",
        "五脏归属：肝属木、心属火、脾属土、肺属金、肾属水。"
      ],
      "c1-l2" => [
        "藏象学说是研究人体脏腑生理功能、病理变化及其相互关系的学说。",
        "五脏主藏精气而不泻；六腑传化物而不藏。",
        "“藏象”之名首见于《素问·六节藏象论》。“象”即外在表现，藏是内在本质。",
        "学习本课时请完成随堂测验，检验对五脏六腑功能的掌握。"
      ],
      "c2-l0" => [
        "望诊是医生运用视觉观察病人全身和局部情况以诊察疾病的方法。",
        "望神：得神、少神、失神、假神；望色：五色主病，青主寒、痛、瘀、惊风。",
        "望舌：舌质反映脏腑气血的盛衰，舌苔反映病邪的深浅与性质。",
        "舌淡白主气血两虚、阳虚；舌红主热证；舌绛主里热亢盛或阴虚火旺。"
      ],
      "c2-l1" => [
        "问诊是获取病情资料的重要手段。明代张景岳总结“十问歌”。",
        "一问寒热二问汗，三问头身四问便，五问饮食六问胸，七聋八渴俱当辨，九问旧病十问因。",
        "主诉采集要抓住最主要、最痛苦的症状及其持续时间。",
        "现病史按发病时间顺序询问，围绕主诉展开。"
      ],
      "c2-l2" => [
        "八纲即阴、阳、表、里、寒、热、虚、实。",
        "表里辨病位浅深，寒热辨病性，虚实辨邪正盛衰，阴阳为总纲。",
        "表证特征：恶寒发热并见、脉浮；里证特征：但热不寒或但寒不热、脉沉。",
        "完成测验，练习八纲辨证的判断。"
      ],
      "c3-l0" => [
        "四气即寒、热、温、凉四种药性；五味即酸、苦、甘、辛、咸。",
        "寒凉药清热泻火、凉血解毒；温热药温里散寒、助阳化气。",
        "升降浮沉反映药物作用趋向：升浮药向上向外，沉降药向下向内。",
        "“酸收、苦降、甘补、辛散、咸软”是五味的基本功效概括。"
      ],
      "c3-l1" => [
        "归经是药物对机体某部分选择性作用的认识，如杏仁归肺经、酸枣仁归心经。",
        "配伍七情：单行、相须、相使、相畏、相杀、相恶、相反。",
        "相须相使为增效配伍，相畏相杀为减毒配伍，相恶相反为配伍禁忌。",
        "十八反、十九畏是临床用药必须遵守的配伍禁忌。"
      ],
      "c3-l2" => [
        "解表药以发散表邪为主要功效，分辛温解表与辛凉解表两类。",
        "麻黄发汗力强，兼能宣肺平喘；桂枝善于温通经脉、助阳化气。",
        "薄荷辛凉透表，兼能疏肝行气、清利头目。",
        "本课时随堂测验考查常用解表药的功效辨识。"
      ],
      "c4-l0" => [
        "麻黄：发汗解表、宣肺平喘、利水消肿，为辛温解表之峻品。",
        "桂枝：发汗解肌、温经通脉、助阳化气，表虚有汗者尤宜。",
        "羌活：祛风散寒、胜湿止痛，善治上半身风寒湿痹。",
        "三药同为辛温，麻黄开腠、桂枝和营、羌活胜湿，应用各有侧重。"
      ],
      "c4-l1" => [
        "薄荷：疏散风热、清利头目、利咽透疹、疏肝行气。",
        "牛蒡子：疏散风热、宣肺祛痰、利咽透疹、解毒散肿。",
        "桑叶：疏散风热、清肺润燥、平抑肝阳、清肝明目。",
        "辛凉解表药多质轻上浮，煎煮时间宜短。"
      ],
      "c4-l2" => [
        "清热药分清热泻火、清热燥湿、清热解毒、清热凉血、清虚热五类。",
        "石膏、知母清肺胃气分实热；黄连、黄芩苦寒燥湿。",
        "金银花、连翘为清热解毒之要药；地黄、牡丹皮凉血止血。",
        "本课时测验考查清热药分类的记忆。"
      ],
      "c5-l0" => [
        "君药：针对主病主证起主要治疗作用的药物，是方中不可缺少的部分。",
        "臣药：辅助君药加强治疗，或针对兼病兼证起治疗作用的药物。",
        "佐药：佐助君药、佐制君药毒性，或反佐的药物。",
        "使药：引经药与调和药，如桂枝汤之甘草调和诸药。"
      ],
      "c5-l1" => [
        "常用剂型：汤剂、丸剂、散剂、膏剂、丹剂、酒剂等。",
        "汤剂吸收快、发挥迅速，便于加减，为临床最常用。",
        "煎药宜用砂锅，武火煮沸后文火慢煎；解表药不宜久煎。",
        "服药时间：补益药多饭前服，对胃肠有刺激的多饭后服。"
      ],
      "c5-l2" => [
        "组方遵循“理、法、方、药”一线贯通：辨证立法，依法立方，以方遣药。",
        "方随证立，药随方遣；主证不变则君药不变。",
        "随证加减：兼证变化时调整臣佐药，保持方之结构完整。",
        "完成随堂测验，理解君臣佐使的组方结构。"
      ],
      "c6-l0" => [
        "桂枝汤由桂枝、芍药、生姜、大枣、甘草五味药组成，为仲景“群方之魁”。",
        "病机为营卫不和、卫强营弱；治以解肌发表、调和营卫。",
        "服后啜热稀粥，温覆取微汗，遍身漐漐微似有汗者益佳。",
        "禁忌：表实无汗、表寒里热及温病初起者不宜使用。"
      ],
      "c6-l1" => [
        "桂枝加厚朴杏子汤：桂枝汤加厚朴、杏仁，主治宿有喘病之人外感风寒。",
        "本方降气平喘兼解表，体现“急则治标、缓则治本”的组方思路。",
        "临床应用把握两点：一是太阳中风证，二是兼有咳喘。",
        "类方对比：桂枝汤调和营卫、桂加葛根治项背强几几。"
      ],
      "c6-l2" => [
        "经方辨证要抓主症与病机，不必拘泥于全部症状齐全。",
        "太阳中风辨证眼目：发热恶风、汗出、脉浮缓。",
        "“有是证，用是方”：证候与方证对应，是经方运用的核心。",
        "完成测验，检验对桂枝汤类方证候要点的掌握。"
      ],
      "c7-l0" => [
        "毫针操作前须检查针具，注意无菌操作。",
        "进针法有指切进针、夹持进针、舒张进针、提捏进针等。",
        "针刺的角度分直刺、斜刺、平刺；深度依腧穴部位与体质而定。",
        "针下得气：医者指下沉紧、患者局部酸麻胀重。"
      ],
      "c7-l1" => [
        "得气是针刺产生疗效的基础，也是施行补泻手法的前提。",
        "常用行针手法：提插法、捻转法。",
        "补泻手法：捻转补泻以顺逆分；提插补泻以轻重急缓分。",
        "“气至病所”往往预示较好疗效，可循经行针引导。"
      ],
      "c7-l2" => [
        "针刺安全要点：眼区、胸背部、颈项部腧穴须严格把握深度与方向。",
        "针下异常情况：滞针、弯针、断针、晕针的处理。",
        "孕妇禁针三阴交、合谷、腹部及腰骶部腧穴。",
        "考核进针、得气与安全规范的要点。"
      ],
      "c8-l0" => [
        "颈椎病针灸治疗以疏通经络、活血止痛为法。",
        "局部取穴：颈夹脊、风池、天柱、肩井；远道取穴：后溪、申脉。",
        "辨证配穴：风寒湿痹加风门、大椎；气滞血瘀加膈俞、血海。",
        "配合温针灸或电针，疗效更佳。"
      ],
      "c8-l1" => [
        "落枕多为睡眠姿势不当，寒邪客于颈项经络所致。",
        "取穴：落枕穴（外劳宫）为经验效穴，配风池、悬钟。",
        "偏头痛多从少阳论治，取外关、足临泣、率谷。",
        "治疗同时嘱患者适度活动颈部，避免再受风寒。"
      ],
      "c8-l2" => [
        "辨证取穴是针灸临床的核心能力：先辨经络归经，再定局部与远道配穴。",
        "本测验围绕颈椎病、落枕、偏头痛的选穴思路设问。",
        "注意区分近部取穴、远部取穴与辨证取穴的不同层次。"
      ],
      "c9-l0" => [
        "感冒分为风寒、风热、暑湿等证。风寒束表：恶寒重发热轻、无汗、脉浮紧。",
        "风热犯表：发热重恶寒轻、咽喉红肿、脉浮数。",
        "风寒感冒代表方：荆防败毒散；风热感冒：银翘散。",
        "治感冒以解表达邪为主，不可过用辛散，以免伤正。"
      ],
      "c9-l1" => [
        "咳嗽分外感与内伤两大类。外感咳嗽起病急，病程短，常伴表证。",
        "风寒袭肺：疏风散寒、宣肺止咳——三拗汤合止嗽散。",
        "风热犯肺：疏风清热、宣肺止咳——桑菊饮。",
        "内伤咳嗽重在调理脏腑，如痰湿蕴肺用二陈汤合三子养亲汤。"
      ],
      "c9-l2" => [
        "肺系辨证测验：综合感冒、咳嗽病案，练习风寒风热的鉴别。",
        "关键鉴别点：恶寒与发热的孰轻孰重、有无汗出、舌脉表现。",
        "答题后请查看解析，巩固辨证思路。"
      ],
      "c10-l0" => [
        "治未病思想源于《素问·四气调神大论》：“圣人不治已病治未病”。",
        "未病先防：调摄精神、加强锻炼、顺应四时、药物预防。",
        "既病防变：早期诊治，截断病势，防止传变。",
        "瘥后防复：注意调养，防止疾病复发。"
      ],
      "c10-l1" => [
        "春生夏长，秋收冬藏。养生须顺应四时阴阳。",
        "春宜养肝，夜卧早起，广步于庭；夏宜养心，无厌于日。",
        "秋宜养肺，收敛神气；冬宜养肾，早卧晚起，去寒就温。",
        "四季食疗各有侧重：春夏养阳，秋冬养阴。"
      ],
      "c10-l2" => [
        "食疗配伍遵循“气味合而服之，以补精益气”。",
        "山药、莲子健脾止泻；百合、麦冬润肺；枸杞、菊花养肝明目。",
        "药食同源之品可日常食用，但需辨体质而用。",
        "本节内容以理解养生原则为主。"
      ],
      :default => [
        "本节为补充阅读材料。",
        "建议结合课程讲义与课后测验巩固所学内容。"
      ]
    }
  end

  # ── 测验题库 ────────────────────────────────────────────────────────────────

  def exams do
    [
      %{
        id: "e1",
        title: "中医基础·阶段性测验（一）",
        duration_min: 20,
        total_points: 100,
        pass_score: 60,
        questions: Questions.pick(["q1", "q2", "q3", "q4", "q5"])
      },
      %{
        id: "e2",
        title: "中药方剂综合测验",
        duration_min: 25,
        total_points: 100,
        pass_score: 60,
        questions: Questions.pick(["q6", "q7", "q8", "q9", "q10"])
      },
      %{
        id: "e3",
        title: "临床辨证·期末模拟卷",
        duration_min: 30,
        total_points: 100,
        pass_score: 60,
        questions: Questions.pick(["q11", "q12", "q13", "q14", "q15", "q16", "q17", "q18"])
      }
    ]
  end

  def exam(id), do: Enum.find(exams(), &(&1.id == id))

  def lesson_quiz(lesson_id) do
    quiz_map = %{
      "c1-l2" => "q1",
      "c2-l2" => "q4",
      "c3-l2" => "q7",
      "c5-l2" => "q9",
      "c7-l2" => "q13",
      "c9-l2" => "q17"
    }

    case Map.get(quiz_map, lesson_id) do
      nil -> nil
      qid -> Questions.get(qid)
    end
  end

  # ── 模拟患者 ────────────────────────────────────────────────────────────────

  def simulated_patients do
    [
      %{
        id: "sp1",
        name: "王秀兰",
        age: 56,
        gender: "女",
        occupation: "退休教师",
        chief_complaint: "反复咳嗽咯痰三年，加重一周",
        opening: "大夫您好，我这咳嗽三四年了，老是好不彻底，最近一周又加重了，晚上咳得睡不好觉。",
        answers: [
          "痰是白色的，比较稀，早上起来多一点。",
          "平时总觉得没力气，怕冷，手脚冰凉。",
          "胃口一般，大便偏稀，一天一两次。",
          "舌苔我照过镜子，有点白白的，比较厚。"
        ],
        dialectic_options: [
          "风寒束肺",
          "痰湿蕴肺",
          "肺脾气虚",
          "阴虚燥咳"
        ],
        correct_dialectic: 2,
        evaluation: %{
          syndrome: "肺脾气虚，痰湿蕴肺",
          reasoning: "患者咳痰稀白、乏力、畏寒、便溏、舌苔白厚，一派脾虚失运、痰湿内停之象。咳嗽反复发作属本虚标实，治疗当健脾化痰、培土生金。",
          pathway: ["六君子汤合二陈汤加减", "参苓白术散化裁", "配合艾灸足三里、脾俞"]
        }
      },
      %{
        id: "sp2",
        name: "刘志强",
        age: 45,
        gender: "男",
        occupation: "货车司机",
        chief_complaint: "右侧头痛三天，胀痛难忍",
        opening: "大夫，我右边太阳穴这儿疼了三天了，一跳一跳的胀疼，一生气更厉害。",
        answers: [
          "疼的时候嘴里发苦，眼睛也有些胀。",
          "平时睡眠不太好，容易急躁发火。",
          "大小便基本正常，就是最近有点便秘。",
          "舌边有点红，舌苔偏黄。"
        ],
        dialectic_options: [
          "肝阳上亢",
          "少阳头痛（肝胆火旺）",
          "风寒头痛",
          "血虚头痛"
        ],
        correct_dialectic: 1,
        evaluation: %{
          syndrome: "少阳头痛，肝胆火旺",
          reasoning: "头痛偏于右侧太阳穴（少阳经循行）、胀痛、口苦、急躁、舌边红苔黄，为肝胆火旺上扰清窍。",
          pathway: ["龙胆泻肝汤加减清泻肝胆", "远道取穴：外关、足临泣（少阳经穴）", "调畅情志，忌辛辣"]
        }
      },
      %{
        id: "sp3",
        name: "赵玉梅",
        age: 32,
        gender: "女",
        occupation: "公司职员",
        chief_complaint: "月经量少、推迟三个月",
        opening: "医生，我这三个月月经都不太正常，量很少，还总是推迟十来天，有些担心。",
        answers: [
          "平时工作压力大，经常熬夜，睡眠浅。",
          "手脚容易冰凉，面色有点发白。",
          "月经颜色偏暗，有少量血块。",
          "舌淡，苔薄白。"
        ],
        dialectic_options: [
          "气滞血瘀",
          "肝血不足（血虚）",
          "肾阳虚",
          "湿热蕴结"
        ],
        correct_dialectic: 1,
        evaluation: %{
          syndrome: "肝血不足，冲任失养",
          reasoning: "月经量少推迟、面色发白、手足凉、舌淡，结合熬夜耗伤阴血，为血虚冲任失养之证。",
          pathway: ["四物汤加减养血调经", "八珍汤化裁气血双补", "规律作息，疏肝健脾"]
        }
      }
    ]
  end

  def simulated_patient(id), do: Enum.find(simulated_patients(), &(&1.id == id))

  # ── MDT 会诊 ───────────────────────────────────────────────────────────────

  def mdt_rooms do
    [
      %{
        id: "m1",
        title: "老年糖尿病合并周围神经病变",
        patient_summary: "男，68岁，糖尿病史12年，双下肢麻木刺痛半年，夜间加重。",
        status: :active,
        participants: [
          mdt_doctor("内分泌科", "孙主任"),
          mdt_doctor("针灸科", "周老师"),
          mdt_doctor("中医内科", "钱老师")
        ],
        messages: [
          %{
            speaker: "孙主任",
            department: "内分泌科",
            role: :doctor,
            text: "患者糖化血红蛋白 8.2%，周围神经病变诊断明确，西药已调整，请中医会诊。",
            time: "10:02"
          },
          %{
            speaker: "周老师",
            department: "针灸科",
            role: :doctor,
            text: "可予温针灸足三里、三阴交、阳陵泉，配合中药泡脚，活血通络。",
            time: "10:05"
          },
          %{
            speaker: "钱老师",
            department: "中医内科",
            role: :doctor,
            text: "病机属气阴两虚、瘀血阻络，建议黄芪桂枝五物汤加减。",
            time: "10:09"
          }
        ]
      },
      %{
        id: "m2",
        title: "顽固性失眠的中医综合方案",
        patient_summary: "女，41岁，入睡困难两年余，多梦易醒，白天乏力，情绪焦虑。",
        status: :waiting,
        participants: [mdt_doctor("中医内科", "钱老师"), mdt_doctor("心理科", "吴老师")],
        messages: [
          %{
            speaker: "钱老师",
            department: "中医内科",
            role: :doctor,
            text: "考虑心脾两虚、心神失养，拟归脾汤加减，配合耳穴压豆。",
            time: "昨天 16:30"
          },
          %{
            speaker: "吴老师",
            department: "心理科",
            role: :doctor,
            text: "建议同步进行睡眠卫生教育，减少白天卧床时间。",
            time: "昨天 16:47"
          }
        ]
      }
    ]
  end

  def mdt_room(id), do: Enum.find(mdt_rooms(), &(&1.id == id))

  defp mdt_doctor(department, name) do
    %{name: name, department: department}
  end

  # ── 通知 ────────────────────────────────────────────────────────────────────

  def notifications do
    [
      %{id: "n1", title: "新课程上线", body: "《中医治未病与养生》已开放选课，欢迎选修。", time: "今天 09:12", read: false},
      %{id: "n2", title: "测验成绩已出", body: "中药方剂综合测验成绩已发布，请查看解析。", time: "昨天 16:40", read: false},
      %{id: "n3", title: "模拟患者任务", body: "王秀兰病例已分配给您，请在一周内完成接诊。", time: "前天 11:05", read: true},
      %{
        id: "n4",
        title: "MDT 会诊邀请",
        body: "您被邀请参加「老年糖尿病合并周围神经病变」会诊。",
        time: "09-28 15:20",
        read: true
      }
    ]
  end

  # ── 学习资料 ────────────────────────────────────────────────────────────────

  # 演示用公开 PDF（离线时可用系统查看器打开）
  @pdf_dummy "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"
  @pdf_sample "https://mozilla.github.io/pdf.js/web/compressed.tracemonkey-pldi-09.pdf"

  def resources do
    [
      %{id: "r1", title: "中医基础理论教学大纲.pdf", type: "PDF", size: "2.4 MB", url: @pdf_dummy},
      %{id: "r2", title: "十四经循行示意图.pdf", type: "PDF", size: "1.8 MB", url: @pdf_sample},
      %{id: "r3", title: "方剂学歌诀手册.pdf", type: "PDF", size: "3.1 MB", url: @pdf_dummy},
      %{id: "r4", title: "中药饮片辨识图册.pdf", type: "PDF", size: "5.6 MB", url: @pdf_sample},
      %{id: "r5", title: "八纲辨证思维导图.pdf", type: "PDF", size: "890 KB", url: @pdf_dummy},
      %{id: "r6", title: "伤寒论条文精读讲义.pdf", type: "PDF", size: "4.2 MB", url: @pdf_sample}
    ]
  end

  # ── 演示账号 ────────────────────────────────────────────────────────────────

  def demo_student do
    %{id: "s1", name: "李明", email: "student@tcm.edu.cn", tenant: "tenant_default", avatar: "李"}
  end
end
