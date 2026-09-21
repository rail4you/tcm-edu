defmodule TcmEdu.Storage.Attachment do
  @moduledoc """
  Attachment resource linking blobs to parent records (Post).

  Each attachment connects a blob (file) to a specific parent record
  and attachment slot (e.g. `:cover_image`, `:attachments`).
  """

  use Ash.Resource,
    domain: TcmEdu.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table("storage_attachments")
    repo(TcmEdu.Repo)

    references do
      reference(:post, on_delete: :nilify)
    end
  end

  attachment do
    blob_resource(TcmEdu.Storage.Blob)
    belongs_to_resource(:post, TcmEdu.Post)
  end

  attributes do
    uuid_primary_key(:id)
  end
end
