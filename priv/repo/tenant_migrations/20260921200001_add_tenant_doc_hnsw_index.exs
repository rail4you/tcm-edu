defmodule TcmEdu.Repo.TenantMigrations.AddTenantDocHnswIndex do
  @moduledoc """
  HNSW 向量索引：租户知识库 >10k 文档时保证余弦检索不退化。

  手写迁移（非 codegen）：custom_statements 生成的 execute 不套 schema prefix，
  而资源内无法引用迁移时的 prefix()，因此这里用 execute/1 + "\#{prefix()}"
  显式限定（租户 slug 可能含连字符，schema 名必须加双引号）。
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX IF NOT EXISTS tenant_docs_full_text_vector_hnsw_idx
    ON "#{prefix()}".tenant_docs USING hnsw (full_text_vector vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS #{prefix()}.\"tenant_docs_full_text_vector_hnsw_idx\"")
  end
end