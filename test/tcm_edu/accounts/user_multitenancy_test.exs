defmodule TcmEdu.Accounts.UserMultitenancyTest do
  @moduledoc """
  Phase 3 测试：User 多租户 + 角色策略。

  覆盖（对照 docs/tcm-edu-progress.md §3.4）：
    * tenant_default 内注册 admin/teacher/student → Bcrypt 可验证
    * role 约束：旧 :admin/:user 被拒绝；新三角色通过；密码 <8 被拒绝
    * student 不能 list_users / list_students（forbidden）
    * teacher 能 list_students；tenant_admin 能 list_users
    * 用户能改自己 profile；不能改他人 profile；admin 能改他人
    * change_password 本人可用
    * update_role / update_status / destroy 仅 admin
    * 通用 :update 不能被 student 用来提权改 role
    * 跨租户隔离：A 租户数据在 B 租户不可见
  """

  use TcmEdu.DataCase, async: false

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.Organization
  alias TcmEdu.Repo

  @tenant "tenant_default"

  describe "role constraints" do
    test "rejects legacy :admin / :user roles" do
      for bad_role <- [:admin, :user] do
        assert {:error, %Ash.Error.Invalid{}} =
                 User
                 |> Ash.Changeset.for_action(:register_with_role, %{
                   email: "bad-#{bad_role}-#{uniq()}@example.com",
                   password: "password123",
                   role: bad_role
                 })
                 |> Ash.create(tenant: @tenant, authorize?: false),
               "role #{inspect(bad_role)} should have been rejected"
      end
    end

    test "accepts :tenant_admin / :teacher / :student" do
      for role <- [:tenant_admin, :teacher, :student] do
        assert {:ok, %User{role: ^role}} =
                 User
                 |> Ash.Changeset.for_action(:register_with_role, %{
                   email: "#{role}-#{uniq()}@example.com",
                   password: "password123",
                   role: role
                 })
                 |> Ash.create(tenant: @tenant, authorize?: false)
      end
    end

    test "rejects password shorter than 8 chars" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               User
               |> Ash.Changeset.for_action(:register_with_role, %{
                 email: "short-#{uniq()}@example.com",
                 password: "short",
                 role: :student
               })
               |> Ash.create(tenant: @tenant, authorize?: false)

      assert Enum.any?(errors, fn %{field: f} -> f == :password end)
    end

    test "bcrypt hash verifies" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_action(:register_with_role, %{
          email: "bcrypt-#{uniq()}@example.com",
          password: "password123",
          role: :student
        })
        |> Ash.create(tenant: @tenant, authorize?: false)

      assert Bcrypt.verify_pass("password123", user.hashed_password)
      refute Bcrypt.verify_pass("wrong", user.hashed_password)
    end
  end

  describe "list policies" do
    setup do
      admin = create_user!("phase3-admin", :tenant_admin)
      teacher = create_user!("phase3-teacher", :teacher)
      student = create_user!("phase3-student", :student)
      {:ok, admin: admin, teacher: teacher, student: student}
    end

    test "tenant_admin can list_users", %{admin: admin} do
      assert {:ok, users} = Ash.read(User, action: :list_users, actor: admin, tenant: @tenant)
      assert length(users) >= 3
    end

    test "teacher can list_users and list_students", %{teacher: teacher} do
      assert {:ok, _} = Ash.read(User, action: :list_users, actor: teacher, tenant: @tenant)

      assert {:ok, students} =
               Ash.read(User, action: :list_students, actor: teacher, tenant: @tenant)

      assert Enum.all?(students, &(&1.role == :student))
    end

    test "student cannot list_users or list_students", %{student: student} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(User, action: :list_users, actor: student, tenant: @tenant)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(User, action: :list_students, actor: student, tenant: @tenant)
    end

    test "student can read self", %{student: student} do
      assert {:ok, fetched} =
               Ash.get(User, student.id, actor: student, tenant: @tenant)

      assert fetched.id == student.id
    end

    test "teacher cannot list_admins", %{teacher: teacher} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(User, action: :list_admins, actor: teacher, tenant: @tenant)
    end

    test "tenant_admin can list_admins", %{admin: admin} do
      assert {:ok, admins} = Ash.read(User, action: :list_admins, actor: admin, tenant: @tenant)
      assert Enum.all?(admins, &(&1.role == :tenant_admin))
    end

    test "anonymous can read teacher profiles", %{teacher: teacher} do
      assert {:ok, profiles} =
               Ash.read(User, action: :list_teacher_profiles, actor: nil, tenant: @tenant)

      assert Enum.any?(profiles, &(&1.id == teacher.id))
      assert Enum.all?(profiles, &(&1.role == :teacher and &1.status == :active))
    end
  end

  describe "write policies" do
    setup do
      admin = create_user!("phase3-w-admin", :tenant_admin)
      student = create_user!("phase3-w-student", :student)
      other = create_user!("phase3-w-other", :student)
      {:ok, admin: admin, student: student, other: other}
    end

    test "student cannot register new users", %{student: student} do
      assert {:error, %Ash.Error.Forbidden{}} =
               User
               |> Ash.Changeset.for_action(:register_with_role, %{
                 email: "nope-#{uniq()}@example.com",
                 password: "password123",
                 role: :student
               })
               |> Ash.create(actor: student, tenant: @tenant)
    end

    test "tenant_admin can register", %{admin: admin} do
      assert {:ok, %User{role: :student}} =
               User
               |> Ash.Changeset.for_action(:register_with_role, %{
                 email: "newbie-#{uniq()}@example.com",
                 password: "password123",
                 role: :student
               })
               |> Ash.create(actor: admin, tenant: @tenant)
    end

    test "student can update own profile, not others'", %{student: student, other: other} do
      assert {:ok, %{name: "New Name"}} =
               other
               |> Ash.Changeset.for_update(:update_profile, %{name: "New Name"})
               |> Ash.update(actor: other, tenant: @tenant)

      # student 试图改 other 的资料 → 拒绝（record 是 other，actor 是 student）
      assert {:error, %Ash.Error.Forbidden{}} =
               other
               |> Ash.Changeset.for_update(:update_profile, %{name: "Hacked"})
               |> Ash.update(actor: student, tenant: @tenant)
    end

    test "tenant_admin can update other's profile", %{admin: admin, student: student} do
      assert {:ok, %{name: "Admin Set"}} =
               student
               |> Ash.Changeset.for_update(:update_profile, %{name: "Admin Set"})
               |> Ash.update(actor: admin, tenant: @tenant)
    end

    test "student cannot use generic :update to escalate role", %{student: student} do
      assert {:error, %Ash.Error.Forbidden{}} =
               student
               |> Ash.Changeset.for_update(:update, %{})
               |> Ash.update(actor: student, tenant: @tenant)
    end

    test "student cannot update_role", %{student: student, other: other} do
      assert {:error, %Ash.Error.Forbidden{}} =
               other
               |> Ash.Changeset.for_update(:update_role, %{role: :teacher})
               |> Ash.update(actor: student, tenant: @tenant)
    end

    test "tenant_admin can update_role and update_status", %{admin: admin, student: student} do
      assert {:ok, %{role: :teacher}} =
               student
               |> Ash.Changeset.for_update(:update_role, %{role: :teacher})
               |> Ash.update(actor: admin, tenant: @tenant)

      assert {:ok, %{status: :disabled}} =
               student
               |> Ash.Changeset.for_update(:update_status, %{status: :disabled})
               |> Ash.update(actor: admin, tenant: @tenant)
    end

    test "change_password works for self", %{student: student} do
      assert {:ok, _} =
               student
               |> Ash.Changeset.for_update(:change_password, %{
                 current_password: "password123",
                 password: "newpassword123",
                 password_confirmation: "newpassword123"
               })
               |> Ash.update(actor: student, tenant: @tenant)
    end

    test "student cannot destroy users", %{student: student, other: other} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.destroy(other, actor: student, tenant: @tenant)
    end
  end

  describe "cross-tenant isolation" do
    test "rows in tenant A are invisible in tenant B" do
      org_a = create_org!("phase3-iso-a")
      org_b = create_org!("phase3-iso-b")

      {:ok, admin_a} =
        User
        |> Ash.Changeset.for_action(:register_with_role, %{
          email: "admin-a-#{uniq()}@example.com",
          password: "password123",
          role: :tenant_admin
        })
        |> Ash.create(tenant: org_a.schema_name, authorize?: false)

      {:ok, _admin_b} =
        User
        |> Ash.Changeset.for_action(:register_with_role, %{
          email: "admin-b-#{uniq()}@example.com",
          password: "password123",
          role: :tenant_admin
        })
        |> Ash.create(tenant: org_b.schema_name, authorize?: false)

      # A 的 admin 在 A 能列出自己
      assert {:ok, users_a} =
               Ash.read(User, action: :list_users, actor: admin_a, tenant: org_a.schema_name)

      assert Enum.any?(users_a, &(&1.id == admin_a.id))

      # A 的 admin 在 B 列不出 A 的用户（schema 级隔离）
      assert {:ok, users_b} =
               Ash.read(User, action: :list_users, actor: admin_a, tenant: org_b.schema_name)

      refute Enum.any?(users_b, &(&1.id == admin_a.id))

      # 直接 get 跨租户返回 not found（行不在该 schema）
      assert {:error, _} = Ash.get(User, admin_a.id, actor: admin_a, tenant: org_b.schema_name)
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(prefix, role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "#{prefix}-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_org!(slug_root) do
    slug = "#{slug_root}-#{uniq()}"
    org = Ash.create!(Organization, %{name: slug, slug: slug}, authorize?: false)
    register_org_cleanup(org)
    org
  end

  defp register_org_cleanup(%Organization{} = org) do
    on_exit(fn ->
      try do
        if schema_exists?(org.schema_name) do
          Repo.query("DROP SCHEMA IF EXISTS \"#{org.schema_name}\" CASCADE")
        end
      rescue
        _ -> :ok
      end
    end)
  end

  defp schema_exists?(name) do
    case Repo.query("SELECT 1 FROM pg_namespace WHERE nspname = $1", [name]) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end
end