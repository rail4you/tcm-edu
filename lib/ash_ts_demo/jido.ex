defmodule AshTsDemo.Jido do
  @moduledoc """
  Jido instance module for the ash-ts-demo application.

  Provides the supervision tree for Jido agents and convenience
  functions for starting/querying agents.
  """
  use Jido, otp_app: :ash_ts_demo
end
