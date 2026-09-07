defmodule TcmEdu.System.SuperAdminTest do
  @moduledoc """
  Tests for the SuperAdmin resource + sign_in_with_password action.

  Covers:
    * `register` action creates a SuperAdmin with bcrypt-hashed password
    * `sign_in_with_password` returns token for valid credentials
    * `sign_in_with_password` returns :invalid_credentials for bad password
    * `sign_in_with_password` returns :invalid_credentials for unknown email
    * touch_last_login updates last_login_at
  """

  use TcmEdu.DataCase, async: false

  alias TcmEdu.System.SuperAdmin
  alias TcmEduWeb.AuthToken

  @valid_attrs %{
    email: "test-admin@example.com",
    name: "Test Admin",
    password: "password123"
  }

  describe "register/2" do
    test "creates a super admin with bcrypt-hashed password" do
      assert {:ok, %SuperAdmin{} = admin} =
               SuperAdmin
               |> Ash.Changeset.for_action(:register, @valid_attrs)
               |> Ash.create(authorize?: false)

      assert to_string(admin.email) == @valid_attrs.email
      assert admin.name == @valid_attrs.name
      assert is_binary(admin.hashed_password)
      assert admin.hashed_password != @valid_attrs.password
      assert String.starts_with?(admin.hashed_password, "$2")  # bcrypt prefix
    end

    test "rejects password shorter than 8 chars" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               SuperAdmin
               |> Ash.Changeset.for_action(:register, Map.put(@valid_attrs, :password, "short"))
               |> Ash.create(authorize?: false)

      assert Enum.any?(errors, fn
        %{field: :password} -> true
        _ -> false
      end)
    end
  end

  describe "sign_in_with_password/2" do
    setup do
      # Register a fresh admin for the test (uses different email to avoid
      # conflict with the production-seeded admin@example.com)
      attrs = %{email: "test-signin@example.com", name: "Test", password: "password123"}
      assert {:ok, %SuperAdmin{} = admin} =
               SuperAdmin
               |> Ash.Changeset.for_action(:register, attrs)
               |> Ash.create(authorize?: false)

      {:ok, admin: admin}
    end

    test "returns token + admin for valid credentials", %{admin: admin} do
      input =
        Ash.ActionInput.for_action(SuperAdmin, :sign_in_with_password, %{
          email: to_string(admin.email),
          password: "password123"
        })

      assert {:ok, %{admin: returned, token: token}} =
               Ash.run_action(input, authorize?: false)

      assert returned.id == admin.id
      assert is_binary(token)

      # Verify the token
      assert {:ok, claims} = AuthToken.verify(token)
      assert claims["tenant"] == "public"
      assert claims["role"] == "super_admin"
      assert claims["sub"] == "user?id=#{admin.id}"
    end

    test "returns :invalid_credentials for wrong password" do
      input =
        Ash.ActionInput.for_action(SuperAdmin, :sign_in_with_password, %{
          email: "test-signin@example.com",
          password: "wrong-password"
        })

      assert {:error, _} = Ash.run_action(input, authorize?: false)
    end

    test "returns :invalid_credentials for unknown email" do
      input =
        Ash.ActionInput.for_action(SuperAdmin, :sign_in_with_password, %{
          email: "nobody@example.com",
          password: "password123"
        })

      assert {:error, _} = Ash.run_action(input, authorize?: false)
    end
  end

  describe "touch_last_login/2" do
    test "updates last_login_at" do
      assert {:ok, %SuperAdmin{} = admin} =
               SuperAdmin
               |> Ash.Changeset.for_action(:register, @valid_attrs)
               |> Ash.create(authorize?: false)

      assert admin.last_login_at == nil

      assert {:ok, %SuperAdmin{last_login_at: %DateTime{}}} =
               admin
               |> Ash.Changeset.for_update(:touch_last_login, %{})
               |> Ash.update(authorize?: false)
    end
  end
end