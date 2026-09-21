defmodule TcmEdu.Chat.ChatMessage do
  @moduledoc """
  A single message in a chat session.
  """

  use Ash.Resource,
    otp_app: :tcm_edu,
    domain: TcmEdu.ChatDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("chat_messages")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :session_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :role, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :metadata, :map do
      default(%{})
      public?(true)
      description("附加元数据：如 AI 回答引用的知识库文档（references）")
    end

    create_timestamp(:inserted_at, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:session_id, :role, :content, :metadata])
    end

    read :for_session do
      argument(:session_id, :string, allow_nil?: false)
      filter(expr(session_id == ^arg(:session_id)))
      prepare(build(sort: [inserted_at: :asc]))
    end
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end
end
