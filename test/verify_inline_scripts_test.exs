defmodule TcmEduWeb.VerifyInlineScriptsTest do
  @moduledoc """
  Guards the FOUC fix: on full page loads the theme and the sidebar collapse
  state must be restored *before* first paint, and LiveView's join morph must
  not reset the drawer checkbox afterwards (phx-update="ignore").
  """
  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest

  alias TcmEdu.Accounts.User

  @tenant "tenant_default"

  defp create_teacher(_) do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "verify-inline-#{System.unique_integer([:positive])}@example.com",
          name: "Verify Teacher",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    %{teacher: teacher}
  end

  describe "inline scripts" do
    setup [:create_teacher]

    test "root layout ships unmangled inline theme/sidebar restore scripts", %{
      conn: conn,
      teacher: teacher
    } do
      conn =
        Plug.Test.init_test_session(conn, %{
          "teacher_id" => teacher.id,
          "teacher_role" => "teacher",
          "teacher_tenant" => @tenant,
          "teacher_email" => to_string(teacher.email),
          "teacher_name" => "Verify Teacher"
        })

      {:ok, _view, html} = live(conn, ~p"/teacher")

      # head script: theme restore from localStorage BEFORE first paint
      assert html =~ "localStorage.getItem(\"tcm-theme\")"
      assert html =~ "document.documentElement.setAttribute(\"data-theme\", t)"
      # portal default: teacher -> tcm
      assert html =~ ~S|location.pathname.indexOf("/teacher") === 0 ? "tcm" : "light"|

      # drawer toggle: restore script right after the checkbox + ignore morph
      assert html =~
               ~S|id="teacher-drawer" type="checkbox" class="drawer-toggle" phx-update="ignore"|

      assert html =~ ~S|t.checked = saved === null ? true : saved === "1"|
      assert html =~ ~S|t.closest("[data-collapse-key]")|
    end
  end
end
