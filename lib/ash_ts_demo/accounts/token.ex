defmodule AshTsDemo.Accounts.Token do
  @moduledoc """
  Token resource required by AshAuthentication for storing token metadata.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource],
    authorizers: [Ash.Policy.Authorizer],
    domain: AshTsDemo.Accounts

  postgres do
    table("tokens")
    repo(AshTsDemo.Repo)
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end
  end
end
