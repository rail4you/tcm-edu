defmodule TcmMobile.Data.Ai do
  @moduledoc """
  本地规则式 AI —— 离线优先：学习问答、模拟患者接诊、MDT 会诊的应答引擎。

  当后端接入真实大模型（`TcmMobile.Api` 切换到 `:remote`）后，这些规则
  由服务端智能回复替代，界面层不变。
  """

  # ── 学习问答（QA Chat）──────────────────────────────────────────────────────

  @doc "根据学生提问返回带中医知识点的回答。"
  def qa_reply(text) do
    cond do
      String.contains?(text, "阴阳") ->
        "阴阳是中医理论的核心。阴阳对立制约、互根互用、消长平衡、相互转化。临床上「善诊者，察色按脉，先别阴阳」，辨清阴阳是辨证总纲。建议结合《中医基础理论精讲》导论课时学习。"

      String.contains?(text, "五行") ->
        "五行相生：木→火→土→金→水；相克：木→土→水→火→金。五脏归属：肝木、心火、脾土、肺金、肾水。记住「生我者为母，我生者为子」，母子相及是常见的传变规律。"

      String.contains?(text, "舌") or String.contains?(text, "苔") ->
        "望舌是四诊之要。舌质反映脏腑气血盛衰，舌苔反映病邪深浅与性质。舌淡白主气血两虚或阳虚，舌红主热证，舌绛主里热亢盛。苔白主寒主表，苔黄主热，苔腻主湿浊痰饮。"

      String.contains?(text, "脉") ->
        "脉诊「浮沉分表里，迟数辨寒热」。浮脉主表，沉脉主里，迟脉主寒，数脉主热。脉象须「四诊合参」，不可单凭脉断病。建议练习《中医诊断学》问诊课时中的脉诊示例。"

      String.contains?(text, "桂枝") or String.contains?(text, "伤寒") ->
        "桂枝汤由桂枝、芍药、生姜、大枣、甘草组成，为仲景「群方之魁」，主治太阳中风之营卫不和。服后啜热稀粥、温覆取微汗。表实无汗者忌用。可深入学习《经方十讲·桂枝汤类方》。"

      String.contains?(text, "感冒") or String.contains?(text, "咳嗽") ->
        "感冒首辨风寒风热：风寒恶寒重发热轻、无汗、脉浮紧，用荆防败毒散；风热发热重恶寒轻、咽红、脉浮数，用银翘散。咳嗽外感多起病急伴表证，内伤重在调脏腑。详见《中医内科·肺系病证》。"

      String.contains?(text, "针灸") or String.contains?(text, "穴") ->
        "针灸取穴分近部、远部与辨证取穴三层。如颈椎病局部取颈夹脊、风池，远道取后溪（通督脉）。得气是疗效基础，表现为指下沉紧、局部酸麻胀重。详见《针灸学入门》。"

      String.contains?(text, "药") or String.contains?(text, "中药") ->
        "中药学核心是「四气五味、升降浮沉、归经」。寒凉药清热，温热药散寒；辛散、甘补、苦降、酸收、咸软。麻黄发汗宣肺、桂枝温通经脉，同属辛温解表药而各有侧重。"

      String.contains?(text, "养生") or String.contains?(text, "体质") ->
        "治未病讲「未病先防、既病防变、瘥后防复」。四季养生：春养肝、夏养心、秋养肺、冬养肾，顺应四时阴阳。可参考《中医治未病与养生》课时。"

      true ->
        "这个问题很值得探讨。建议你在「课程」页选择相关专题深入学习，或在课时学习中结合随堂测验检验掌握情况。也可以把具体病案发给我，我帮你梳理辨证思路。"
    end
  end

  # ── 模拟患者（SP）───────────────────────────────────────────────────────────

  @doc """
  模拟患者的下一步应答。

  返回 `{reply_text, new_shown_count}`。当患者已把病史讲完（answers 用尽），
  提示学员进行辨证论治；若已提交辨证，则不再追问。
  """
  def sp_reply(patient, shown_count, _text) do
    answers = Map.get(patient, :answers, [])

    cond do
      shown_count < length(answers) ->
        reply = Enum.at(answers, shown_count)
        {reply, shown_count + 1}

      true ->
        {"大夫，基本情况就是这些，您看我这病该怎么辨证调理？", shown_count}
    end
  end

  @doc "判断学员的辨证选择是否正确，返回评价结果。"
  def sp_grade(patient, choice_index) do
    correct? = choice_index == Map.get(patient, :correct_dialectic, -1)
    evaluation = Map.get(patient, :evaluation, %{})

    %{
      correct?: correct?,
      syndrome: Map.get(evaluation, :syndrome, "未给出"),
      reasoning: Map.get(evaluation, :reasoning, ""),
      pathway: Map.get(evaluation, :pathway, []),
      patient_name: Map.get(patient, :name, ""),
      chief_complaint: Map.get(patient, :chief_complaint, "")
    }
  end

  # ── MDT 会诊 ────────────────────────────────────────────────────────────────

  @doc "学员发言后，由下一位会诊医生给出回应。"
  def mdt_reply(room, _text) do
    participants = Map.get(room, :participants, [])

    if participants == [] do
      %{speaker: "主持人", role: "会诊", text: "感谢各位参与，本次会诊意见已汇总，请关注后续纪要。"}
    else
      index = rem(Enum.count(Map.get(room, :messages, [])), length(participants))
      doc = Enum.at(participants, index)

      replies = [
        "同意，建议结合舌脉进一步明确证型，完善辨证论治方案。",
        "从整体观念出发，还需兼顾患者情志与生活起居的调护。",
        "同意中医治疗介入，建议中西医结合、定期随访评估疗效。",
        "请在病历中补充四诊信息，便于后续复诊对照。"
      ]

      text = Enum.at(replies, rem(index, length(replies)))
      %{speaker: doc.name, role: doc.department, text: text}
    end
  end

  # ── 随堂测验提示 ────────────────────────────────────────────────────────────

  @doc "课时随堂测验的即时反馈。"
  def quiz_feedback(question, answer_index) do
    if answer_index == question.answer do
      "回答正确！#{question.explanation}"
    else
      "回答错误。正确答案是「#{Enum.at(question.options, question.answer)}」。#{question.explanation}"
    end
  end
end
