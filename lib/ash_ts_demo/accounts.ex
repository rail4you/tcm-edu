defmodule AshTsDemo.Accounts do
  @moduledoc """
  Ash domain hosting authentication resources (User, Token).
  """

  use Ash.Domain,
    otp_app: :ash_ts_demo

  resources do
    resource AshTsDemo.Accounts.User
    resource AshTsDemo.Accounts.Token
  end
end
