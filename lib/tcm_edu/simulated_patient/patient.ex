defmodule TcmEdu.SimulatedPatient.Patient do
  @moduledoc """
  标准化病人（Standardized Patient，SP）档案（租户域）。

  教师在「AI 模拟诊疗」栏目创建病人档案：填写姓名、年龄、性别、人设、
  主诉、现病史、既往史、性格特点、关键问诊要点与评分维度（专业度 / 同理心 /
  沟通技巧）等。学生在教师布置任务后，与该病人进行模拟问诊对话。

  ## 字段约定

    * `profile`     — 病人基础信息（性别、年龄、职业、性格等，结构化 JSON）
    * `complaint`   — 主诉（学生开场需要从这条切入）
    * `history`     — 现病史 / 既往史 / 体格检查 / 辅助检查等背景
    * `personality` — 性格特点与表达风格（指导 AI 在对话中保持一致的口吻）
    * `talking_style` — 说话方式（短句、方言、情绪化、回避敏感话题等）
    * `key_points`  — 评分要点清单（每条一条问诊 / 沟通关键动作）
    * `rubric`      — 评分权重（专业度 / 同理心 / 沟通技巧占比，总和 100）
    * `difficulty`  — 难度 1-5，病人隐藏信息的多少、表达含蓄程度
    * `status`      — `:draft` / `:published` / `:archived`，仅 published 可分配给学生

  多租户：`multitenancy :context`。
  """

  use Ash.Resource,
    domain: TcmEdu.SimulatedPatient,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("simulated_patients")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      description("病人姓名（用于教师端列表与对话展示）")
    end

    attribute :subject, :atom do
      constraints(
        one_of: [
          :traditional_chinese_medicine,
          :western_medicine,
          :anatomy,
          :physiology,
          :pathology,
          :pharmacology,
          :clinical,
          :nursing,
          :public_health,
          :other
        ]
      )

      public?(true)
      description("所属学科")
    end

    attribute :scenario_title, :string do
      public?(true)
      description("情境标题（如：心悸 3 天，加重 1 天）")
    end

    attribute :profile, :map do
      default(%{})
      public?(true)
      description("病人基础信息 JSON：%{age: 52, gender: \"女\", occupation: \"退休教师\"}")
    end

    attribute :complaint, :string do
      allow_nil?(false)
      public?(true)
      description("主诉（一句话概括）")
    end

    attribute :history, :string do
      public?(true)
      description("现病史 / 既往史 / 查体 / 辅助检查等背景")
    end

    attribute :personality, :string do
      public?(true)
      description("性格特点：焦虑、配合、回避、健谈等")
    end

    attribute :talking_style, :string do
      public?(true)
      description("说话方式：句长、方言词、情绪化程度等")
    end

    attribute :key_points, {:array, :string} do
      default([])
      public?(true)
      description("评分要点清单：问诊 / 沟通的关键动作")
    end

    attribute :rubric, :map do
      default(%{"professional" => 50, "empathy" => 25, "communication" => 25})
      public?(true)
      description("评分维度权重：专业度 / 同理心 / 沟通技巧，总和 100")
    end

    attribute :difficulty, :integer do
      default(3)
      constraints(min: 1, max: 5)
      public?(true)
    end

    attribute :difficulty_level, :atom do
      default(:introductory)
      constraints(one_of: [:introductory, :advanced, :expert, :emergency])
      public?(true)
      description("难度分级语义：入门 / 进阶 / 专家 / 急诊")
    end

    attribute :standard_pathway, :map do
      default(%{})
      public?(true)
      description("标准诊疗路径（分阶段标准动作清单），用于实时对比学员思维漏洞")
    end

    attribute :red_flags, {:array, :string} do
      default([])
      public?(true)
      description("急诊危重信号（需优先识别的 red flag），漏诊即警示降级")
    end

    attribute :min_questions, :integer do
      default(5)
      constraints(min: 3, max: 30)
      public?(true)
      description("建议的最少问诊轮次（少于则提示学生继续问诊）")
    end

    attribute :max_turns, :integer do
      default(20)
      constraints(min: 5, max: 100)
      public?(true)
      description("对话最大轮次上限（防止失控）")
    end

    attribute :status, :atom do
      default(:draft)
      constraints(one_of: [:draft, :published, :archived])
      public?(true)
    end

    attribute :created_by_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :created_by_email, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :created_by, TcmEdu.Accounts.User do
      source_attribute(:created_by_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end

    has_many :assignments, TcmEdu.SimulatedPatient.Assignment do
      destination_attribute(:patient_id)
      public?(true)
    end

    has_many :sessions, TcmEdu.SimulatedPatient.Session do
      destination_attribute(:patient_id)
      public?(true)
    end
  end

  aggregates do
    count(:assignment_count, :assignments)
    count(:session_count, :sessions)
  end

  code_interface do
    define(:list_patients, action: :read)
    define(:get_patient, action: :read, get_by: [:id])
    define(:create_patient, action: :create)
    define(:update_patient, action: :update)
    define(:publish_patient, action: :publish)
    define(:archive_patient, action: :archive)
    define(:delete_patient, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      description("教师创建一个新的标准化病人")

      accept([
        :name,
        :subject,
        :scenario_title,
        :profile,
        :complaint,
        :history,
        :personality,
        :talking_style,
        :key_points,
        :rubric,
        :difficulty,
        :difficulty_level,
        :standard_pathway,
        :red_flags,
        :min_questions,
        :max_turns,
        :status,
        :created_by_id,
        :created_by_email
      ])

      validate(present([:complaint]))
      validate(string_length(:complaint, min: 2, max: 500))
      validate(string_length(:history, max: 10_000))
    end

    update :update do
      primary?(true)

      accept([
        :name,
        :subject,
        :scenario_title,
        :profile,
        :complaint,
        :history,
        :personality,
        :talking_style,
        :key_points,
        :rubric,
        :difficulty,
        :difficulty_level,
        :standard_pathway,
        :red_flags,
        :min_questions,
        :max_turns,
        :status
      ])
    end

    update :publish do
      description("发布后学生才可见可分配")
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :published))
    end

    update :archive do
      description("归档：停止分配")
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :archived))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 教师可读所有（自己租户的）；学生只能读 published 且分配给自己的。
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(status == :published))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action([:publish, :archive]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
