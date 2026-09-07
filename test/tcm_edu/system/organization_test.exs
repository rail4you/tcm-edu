defmodule TcmEdu.System.OrganizationTest do
  @moduledoc """
  Tests for the Organization resource + TenantProvisioning.

  Covers:
    * `create_with_schema` action creates the schema and runs migrations
    * `destroy` action drops the schema (CASCADE)
    * Validation of slug uniqueness + format
    * `TenantProvisioning.all_tenant_schemas/0`
    * Status transitions (archive / activate / suspend)

  Note on isolation:

    The SQL sandbox rolls back the public-schema row (the `organizations`
    record) but cannot roll back `CREATE SCHEMA`, so we explicitly register
    `on_exit` cleanup in each test that creates an org.
  """

  use TcmEdu.DataCase, async: false

  alias TcmEdu.System.Organization
  alias TcmEdu.TenantProvisioning
  alias TcmEdu.Repo

  @valid_attrs %{
    name: "Test Academy",
    contact_email: "admin@test.edu",
    description: "A test tenant"
  }

  describe "create_with_schema/1" do
    test "creates organization, schema, and skeleton tables" do
      org = create_org!("test-academy")

      assert org.schema_name == "tenant_" <> org.slug
      assert schema_exists?(org.schema_name)
      assert table_exists?(org.schema_name, "tenant_system_info")
      assert table_exists?(org.schema_name, "schema_migrations")
    end

    test "auto-sets schema_name from slug" do
      org = create_org!("acme")
      assert org.schema_name == "tenant_" <> org.slug
    end

    test "rejects duplicate slug" do
      slug = unique_slug("dup")

      assert {:ok, %Organization{}} =
               Ash.create(Organization, build_attrs(slug), authorize?: false)

      assert {:error, %Ash.Error.Invalid{} = err} =
               Ash.create(Organization, build_attrs(slug), authorize?: false)

      assert has_slug_error?(err)
    end

    test "rejects invalid slug format" do
      bad_slugs = ["UPPERCASE", "-leading-dash", "trailing-dash-", "with spaces", ""]

      Enum.each(bad_slugs, fn slug ->
        assert {:error, _} =
                 Ash.create(Organization, build_attrs(slug), authorize?: false),
               "slug #{inspect(slug)} should have been rejected"
      end)
    end
  end

  describe "destroy/1" do
    test "drops the schema with CASCADE" do
      org = create_org!("to-destroy")

      assert schema_exists?(org.schema_name)

      assert :ok = Ash.destroy!(org, authorize?: false)
      refute schema_exists?(org.schema_name), "schema #{org.schema_name} should have been dropped"
    end
  end

  describe "TenantProvisioning.all_tenant_schemas/0" do
    test "returns only tenant_* schemas" do
      schemas = TenantProvisioning.all_tenant_schemas()
      assert is_list(schemas)
      assert Enum.all?(schemas, &String.starts_with?(&1, "tenant_"))
      refute Enum.any?(schemas, &(&1 == "public"))
    end

    test "includes newly created tenant" do
      org = create_org!("fresh-tenant")

      schemas = TenantProvisioning.all_tenant_schemas()
      assert org.schema_name in schemas
    end
  end

  describe "status transitions" do
    test "archive -> activate -> suspend transitions" do
      org = create_org!("states")

      assert {:ok, %{status: :archived}} =
               org |> Ash.Changeset.for_update(:archive) |> Ash.update(authorize?: false)

      assert {:ok, %{status: :active}} =
               org |> Ash.Changeset.for_update(:activate) |> Ash.update(authorize?: false)

      assert {:ok, %{status: :suspended}} =
               org |> Ash.Changeset.for_update(:suspend) |> Ash.update(authorize?: false)
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp create_org!(slug_root) do
    slug = unique_slug(slug_root)
    org = Ash.create!(Organization, build_attrs(slug), authorize?: false)
    register_cleanup(org)
    org
  end

  defp build_attrs(slug) do
    Map.put(@valid_attrs, :slug, slug)
  end

  defp unique_slug(root) do
    "#{root}-#{System.unique_integer([:positive])}"
  end

  defp register_cleanup(%Organization{} = org) do
    on_exit(fn ->
      try do
        # Always do raw SQL drop so we don't depend on the (now rolled-back)
        # sandbox record. Force CASCADE because the record was rolled back.
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

  defp table_exists?(schema, table) do
    case Repo.query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2",
           [schema, table]
         ) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end

  defp has_slug_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{field: :slug} -> true
      _ -> false
    end)
  end

  defp has_slug_error?(_), do: false
end