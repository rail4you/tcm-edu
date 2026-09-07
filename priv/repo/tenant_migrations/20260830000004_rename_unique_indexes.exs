defmodule TcmEdu.Repo.TenantMigrations.RenameUniqueIndexes do
  @moduledoc """
  把手写迁移里的唯一索引名改成 AshPostgres 约定名。

  背景：Ash 为 identity 生成的 changeset constraint 名是
  `<table>_<identity>_index`（如 `users_unique_email_per_tenant_index`）。
  手写迁移用了 `tenant_`-前缀名，导致唯一冲突时 Ecto 抛出的
  constraint 名对不上，Ash 无法转成友好的 `Invalid` 错误，
  前端会收到 500 而不是 422。因此改名对齐。
  """

  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:users, [:email], name: "tenant_users_unique_email_index")
    create unique_index(:users, [:email], name: "users_unique_email_per_tenant_index")

    drop_if_exists unique_index(:course_categories, [:slug],
                       name: "tenant_course_categories_slug_index"
                     )

    create unique_index(:course_categories, [:slug],
             name: "course_categories_unique_slug_per_tenant_index"
           )
  end

  def down do
    drop_if_exists unique_index(:course_categories, [:slug],
                       name: "course_categories_unique_slug_per_tenant_index"
                     )

    create unique_index(:course_categories, [:slug], name: "tenant_course_categories_slug_index")

    drop_if_exists unique_index(:users, [:email], name: "users_unique_email_per_tenant_index")
    create unique_index(:users, [:email], name: "tenant_users_unique_email_index")
  end
end
