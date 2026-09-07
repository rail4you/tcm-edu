defmodule TcmEdu.Post do
  @moduledoc """
  A Post resource with file attachment support via AshStorage.

  Supports:
    * `cover_image` — a single image attachment (`has_one_attached`)
    * `attachments`  — multiple file attachments (`has_many_attached`)
  """

  use Ash.Resource,
    domain: TcmEdu.PostDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage, AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer],
    otp_app: :tcm_edu

  postgres do
    table("posts")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("Post")
  end

  storage do
    service({AshStorage.Service.Disk, root: "priv/storage", base_url: "/storage"})

    blob_resource(TcmEdu.Storage.Blob)
    attachment_resource(TcmEdu.Storage.Attachment)

    has_one_attached(:cover_image)

    has_many_attached :attachments do
      analyzer(TcmEdu.Storage.Analyzers.VideoInfo)
      analyzer(TcmEdu.Storage.Analyzers.DocumentInfo)

      variant(:thumbnail, {TcmEdu.Storage.Variants.VideoThumbnail, second: 1, width: 640},
        generate: :eager
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 200, trim?: true)
    end

    attribute :body, :string do
      public?(true)
      constraints(max_length: 10_000)
    end

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:title, :body])
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:title, :body])
    end
  end

  policies do
    # Admin can do everything on posts
    policy actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    # Authenticated users can read posts
    policy action_type(:read) do
      authorize_if(actor_present())
    end

    # Users with explicit post:create permission can create
    policy action_type(:create) do
      authorize_if({TcmEdu.Checks.HasPermission, permission: "post:create"})
    end

    # Users with explicit post:update permission can update
    policy action_type(:update) do
      authorize_if({TcmEdu.Checks.HasPermission, permission: "post:update"})
    end

    # Users with explicit post:delete permission can destroy
    policy action_type(:destroy) do
      authorize_if({TcmEdu.Checks.HasPermission, permission: "post:delete"})
    end
  end
end
