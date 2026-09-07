defmodule TcmEdu.Chat.ChatMessage do
  @moduledoc """
  A single message in a chat session.
  """

  use Ash.Resource,
    otp_app: :tcm_edu,
    domain: TcmEdu.ChatDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("chat_messages")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("ChatMessage")
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

    create_timestamp(:inserted_at, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:session_id, :role, :content])
    end
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end
end
