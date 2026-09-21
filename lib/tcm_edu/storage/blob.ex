defmodule TcmEdu.Storage.Blob do
  @moduledoc """
  Blob resource for file metadata in AshStorage.

  Each blob represents a file stored on disk (or in a cloud service).
  Blobs are linked to parent records via attachments.
  """

  use Ash.Resource,
    domain: TcmEdu.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.BlobResource]

  postgres do
    table("storage_blobs")
    repo(TcmEdu.Repo)
  end

  blob do
  end

  attributes do
    uuid_primary_key(:id)
  end
end
