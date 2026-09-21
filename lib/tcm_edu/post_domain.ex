defmodule TcmEdu.PostDomain do
  @moduledoc """
  Ash domain hosting the Post resource with file attachments.
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Post do
      rpc_action(:list_posts, :read)
      rpc_action(:get_post, :read, get?: true)
      rpc_action(:create_post, :create)
      rpc_action(:update_post, :update)
      rpc_action(:delete_post, :destroy)
    end
  end

  resources do
    resource TcmEdu.Post
  end
end
