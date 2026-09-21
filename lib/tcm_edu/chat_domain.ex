defmodule TcmEdu.ChatDomain do
  @moduledoc """
  Domain for chat sessions and messages.
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.Chat.ChatSession
    resource TcmEdu.Chat.ChatMessage
    resource TcmEdu.Chat.ChatTask
  end
end
