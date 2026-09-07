defmodule TcmEdu.ChatDomain do
  @moduledoc """
  Domain for chat sessions and messages, exposed via AshTypescript RPC.
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Chat.ChatSession do
      rpc_action(:list_sessions, :read)
      rpc_action(:get_session, :read, get?: true)
      rpc_action(:create_session, :create)
    end

    resource TcmEdu.Chat.ChatMessage do
      rpc_action(:list_messages, :read)
      rpc_action(:create_message, :create)
    end

    resource TcmEdu.Chat.ChatTask do
      rpc_action(:list_tasks, :read)
      rpc_action(:get_task, :by_task_id)
    end
  end

  resources do
    resource TcmEdu.Chat.ChatSession
    resource TcmEdu.Chat.ChatMessage
    resource TcmEdu.Chat.ChatTask
  end
end
