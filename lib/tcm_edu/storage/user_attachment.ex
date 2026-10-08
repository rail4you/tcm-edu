defmodule TcmEdu.Storage.UserAttachment do
  @moduledoc """
  Polymorphic attachment resource linking blobs to tenant-scoped `User`
  records.

  Users live in per-tenant Postgres schemas while blobs live in `public`,
  so a cross-schema foreign key is impossible. Like
  `TcmEdu.Storage.CourseAttachment`, this resource declares no
  `belongs_to_resource` and links via `record_type` / `record_id` strings.
  """

  use Ash.Resource,
    domain: TcmEdu.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table("storage_user_attachments")
    repo(TcmEdu.Repo)
  end

  attachment do
    blob_resource(TcmEdu.Storage.Blob)
  end

  attributes do
    uuid_primary_key(:id)
  end
end
