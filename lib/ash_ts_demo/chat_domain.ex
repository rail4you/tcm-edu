defmodule AshTsDemo.ChatDomain do
  @moduledoc """
  Domain for chat sessions and messages, exposed via AshTypescript RPC.
  """

  use Ash.Domain,
    otp_app: :ash_ts_demo,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTsDemo.Chat.ChatSession do
      rpc_action(:list_sessions, :read)
      rpc_action(:get_session, :read, get?: true)
      rpc_action(:create_session, :create)
    end

    resource AshTsDemo.Chat.ChatMessage do
      rpc_action(:list_messages, :read)
      rpc_action(:create_message, :create)
    end
  end

  resources do
    resource AshTsDemo.Chat.ChatSession
    resource AshTsDemo.Chat.ChatMessage
  end
end
