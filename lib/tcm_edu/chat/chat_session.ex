defmodule TcmEdu.Chat.ChatSession do
  @moduledoc """
  A chat session groups messages for a specific agent.
  """

  use Ash.Resource,
    otp_app: :tcm_edu,
    domain: TcmEdu.ChatDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("chat_sessions")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :user_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :agent_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      default("New Chat")
      public?(true)
    end

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:user_id, :agent_name, :title])
    end

    update :rename do
      primary?(false)
      accept([:title])
      validate(string_length(:title, min: 1, max: 100))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(expr(user_id == ^actor(:id)))
    end

    policy action_type([:update, :destroy]) do
      authorize_if(expr(user_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(actor_present())
    end
  end
end
