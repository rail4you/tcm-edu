defmodule TcmEdu.PostDomain do
  @moduledoc """
  Ash domain hosting the Post resource with file attachments.
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.Post
  end
end
