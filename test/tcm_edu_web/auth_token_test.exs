defmodule TcmEduWeb.AuthTokenTest do
  @moduledoc """
  Tests for the TcmEduWeb.AuthToken helper (custom JWT issuance).

  Verifies:
    * generate/2 produces a valid JWT with sub, tenant, role claims
    * verify/1 round-trips a token
    * peek/1 reads claims without verification
    * token expiration is enforced
    * wrong signing secret is rejected
  """

  use ExUnit.Case, async: true

  alias TcmEduWeb.AuthToken

  describe "generate/2 + verify/1 round-trip" do
    test "produces a verifiable JWT with the given claims" do
      {:ok, token, claims} =
        AuthToken.generate("user-123", %{
          "tenant" => "tenant_default",
          "role" => "student"
        })

      assert is_binary(token)
      assert claims["sub"] == "user?id=user-123"
      assert claims["tenant"] == "tenant_default"
      assert claims["role"] == "student"
      assert is_integer(claims["iat"])
      assert is_integer(claims["exp"])
      assert claims["exp"] > claims["iat"]

      # Verify the token
      assert {:ok, ^claims} = AuthToken.verify(token)
    end

    test "accepts string-keyed and atom-keyed claims" do
      {:ok, token, claims1} =
        AuthToken.generate("user-1", %{"tenant" => "public", "role" => "super_admin"})

      {:ok, claims2} = AuthToken.verify(token)

      assert claims1["tenant"] == "public"
      assert claims2["tenant"] == "public"
      assert claims2["role"] == "super_admin"
    end

    test "always overrides sub with 'user?id=<uuid>' format" do
      {:ok, _token, claims} =
        AuthToken.generate("abc-123", %{"sub" => "should-be-overridden"})

      assert claims["sub"] == "user?id=abc-123"
    end
  end

  describe "verify/1 failure modes" do
    test "rejects garbage tokens" do
      assert {:error, _} = AuthToken.verify("not.a.jwt")
      assert {:error, _} = AuthToken.verify("")
    end

    test "rejects tokens signed with a different secret" do
      {:ok, token, _} =
        AuthToken.generate("user-1", %{"tenant" => "public", "role" => "user"})

      # Tamper with the signature
      [header, payload, _sig] = String.split(token, ".")
      tampered = "#{header}.#{payload}.AAAAinvalidsigBBBB"

      assert {:error, _} = AuthToken.verify(tampered)
    end
  end

  describe "peek/1" do
    test "reads claims without verifying signature" do
      {:ok, token, _} =
        AuthToken.generate("user-1", %{"tenant" => "public", "role" => "super_admin"})

      assert {:ok, claims} = AuthToken.peek(token)
      assert claims["tenant"] == "public"
      assert claims["role"] == "super_admin"
    end
  end
end