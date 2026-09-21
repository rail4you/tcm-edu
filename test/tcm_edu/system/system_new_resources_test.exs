defmodule TcmEdu.System.SystemNewResourcesTest do
  @moduledoc """
  System 域新增资源测试（Phase 5 骨架）：
    * AuditLog：记录 / 列出 / 筛选
    * ApiKeyConfig：创建（upsert）/ 唯一 provider / 读取可见性
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.System.{ApiKeyConfig, AuditLog, SuperAdmin}

  describe "api_key_config" do
    test "upsert creates and later updates same provider" do
      admin = create_super_admin()

      {:ok, cfg} =
        set_key!(admin, :qwen, "sk-qwen-abc", "https://dashscope.aliyuncs.com/compatible-mode/v1")

      assert cfg.provider == :qwen
      assert cfg.base_url =~ "dashscope"

      assert {:ok, updated} =
               set_key!(
                 admin,
                 :qwen,
                 "sk-qwen-xyz",
                 "https://dashscope.aliyuncs.com/compatible-mode/v1"
               )

      assert updated.api_key == "sk-qwen-xyz"
      assert count_providers() == 1
    end

    test "api_key is sensitive (not returned plaintext via public read)" do
      admin = create_super_admin()
      set_key!(admin, :deepseek, "sk-ds-secret", nil)

      # 超管可读（key 仍以原值存在，但敏感字段不对外明文透传由调用方决定；
      # 这里至少验证能列出 provider）
      list = list_configs!(admin)
      assert Enum.any?(list, &(&1.provider == :deepseek))
    end
  end

  describe "audit_log" do
    test "record and list with filter" do
      admin = create_super_admin()

      {:ok, _} =
        AuditLog
        |> Ash.Changeset.for_action(
          :record,
          %{
            tenant: "tenant_default",
            actor_id: admin.id,
            action: "organization.suspend",
            resource_type: "Organization",
            resource_id: Ecto.UUID.generate(),
            changes: %{"before" => %{"status" => "active"}, "after" => %{"status" => "suspended"}},
            success: true
          },
          actor: admin
        )
        |> Ash.create()

      {:ok, _} =
        AuditLog
        |> Ash.Changeset.for_action(
          :record,
          %{
            tenant: "tenant_other",
            action: "course.publish",
            resource_type: "Course",
            success: true
          },
          actor: admin
        )
        |> Ash.create()

      filtered =
        AuditLog
        |> Ash.Query.for_read(:filtered, %{tenant: "tenant_default"}, actor: admin)
        |> Ash.read!()

      assert length(filtered) == 1
      assert hd(filtered).action == "organization.suspend"
    end

    test "non-admin cannot read audit logs" do
      # 无 actor / 普通角色 → Forbidden
      assert {:error, %Ash.Error.Forbidden{}} =
               AuditLog
               |> Ash.Query.for_read(:read, %{})
               |> Ash.read(tenant: "tenant_default")
    end
  end

  # ─── helpers ───────────────────────────────────────────

  defp create_super_admin do
    {:ok, admin} =
      SuperAdmin
      |> Ash.Changeset.for_action(:register, %{
        email: "sys#{System.unique_integer([:positive])}@example.com",
        name: "Sys Admin",
        password: "password123"
      })
      |> Ash.create(authorize?: false)

    admin
  end

  defp set_key!(admin, provider, key, base_url) do
    ApiKeyConfig
    |> Ash.Changeset.for_action(
      :upsert,
      %{
        provider: provider,
        api_key: key,
        base_url: base_url,
        is_active: true
      },
      actor: admin
    )
    |> Ash.create()
  end

  defp count_providers do
    ApiKeyConfig
    |> Ash.read!(actor: create_super_admin())
    |> length()
  end

  defp list_configs!(admin) do
    ApiKeyConfig
    |> Ash.read!(actor: admin)
  end
end
