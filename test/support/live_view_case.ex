defmodule AshTsDemoWeb.LiveViewCase do
  @moduledoc """
  Test case for LiveView pages. Wraps each test in a SQL sandbox and
  provides the standard `Phoenix.LiveViewTest` helpers.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint AshTsDemoWeb.Endpoint

      use AshTsDemoWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import AshTsDemoWeb.LiveViewCase

      @moduletag :live_view
    end
  end

  setup tags do
    AshTsDemo.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
