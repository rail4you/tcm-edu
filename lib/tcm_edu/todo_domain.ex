defmodule TcmEdu.TodoDomain do
  @moduledoc """
  Ash domain hosting the `Todo` resource.
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource(TcmEdu.Todo)
  end
end
