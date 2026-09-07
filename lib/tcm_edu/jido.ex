defmodule TcmEdu.Jido do
  @moduledoc """
  Jido instance module for the tcm-edu application.

  Provides the supervision tree for Jido agents and convenience
  functions for starting/querying agents.
  """
  use Jido, otp_app: :tcm_edu
end
