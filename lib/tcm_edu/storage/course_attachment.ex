defmodule TcmEdu.Storage.CourseAttachment do
  @moduledoc """
  Polymorphic attachment resource linking blobs to tenant-scoped records
  (currently `TcmEdu.Courses.Course` covers).

  Unlike a FK-bound attachment (e.g. an `Attachment` table with a
  `belongs_to_resource` to a global record), this resource declares
  no `belongs_to_resource`, so links are
  stored as `record_type` / `record_id` strings. This is required because
  courses live in per-tenant Postgres schemas while attachments live in
  `public` — a cross-schema foreign key is impossible.
  """

  use Ash.Resource,
    domain: TcmEdu.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table("storage_course_attachments")
    repo(TcmEdu.Repo)
  end

  attachment do
    blob_resource(TcmEdu.Storage.Blob)
  end

  attributes do
    uuid_primary_key(:id)
  end
end
