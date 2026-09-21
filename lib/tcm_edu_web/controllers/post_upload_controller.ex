defmodule TcmEduWeb.PostUploadController do
  @moduledoc """
  Handles file uploads for Post attachments.

  POST /api/posts/:post_id/upload/:attachment_name

  Expects multipart/form-data with a `file` field containing the uploaded file.
  Authentication via Bearer token.
  """

  use TcmEduWeb, :controller

  def upload(conn, %{"post_id" => post_id, "attachment_name" => attachment_name}) do
    actor = conn.assigns[:current_user] || conn.assigns[:actor]

    with {:ok, %Plug.Upload{} = upload} <- fetch_upload(conn) do
      attachment_name_atom = String.to_existing_atom(attachment_name)

      post_result =
        case actor do
          nil ->
            Ash.get(TcmEdu.Post, post_id, actor: :any, authorize?: false)

          user ->
            Ash.get(TcmEdu.Post, post_id, actor: user)
        end

      case post_result do
        {:ok, post} ->
          # Read file as binary — Operations.attach doesn't handle %Plug.Upload{} for analyzers
          file_data = File.read!(upload.path)

          case AshStorage.Operations.attach(post, attachment_name_atom, file_data,
                 filename: upload.filename,
                 content_type: upload.content_type,
                 actor: :any
               ) do
            {:ok, %{blob: blob, record: record}} ->
              # Load the URL(s) for the newly attached file
              case AshStorage.Info.attachment(TcmEdu.Post, attachment_name_atom) do
                {:ok, att} ->
                  is_one = att.type == :one

                  url_calc =
                    if is_one,
                      do: :"#{attachment_name_atom}_url",
                      else: :"#{attachment_name_atom}_urls"

                  loaded =
                    Ash.load!(record, [url_calc], actor: :any, authorize?: false)

                  json(conn, %{
                    success: true,
                    blob_id: blob.id,
                    url: Map.get(loaded, url_calc),
                    filename: blob.filename
                  })

                :error ->
                  json(conn, %{success: true, blob_id: blob.id, filename: blob.filename})
              end

            {:error, error} ->
              json(conn, %{success: false, error: inspect(error)})
          end

        {:error, error} ->
          json(conn, %{success: false, error: inspect(error)})
      end
    else
      :error ->
        json(conn, %{success: false, error: "No file field in upload"})
    end
  end

  def options(conn, _params), do: json(conn, %{})

  defp fetch_upload(conn) do
    case Map.fetch(conn.params, "file") do
      {:ok, %Plug.Upload{} = upload} -> {:ok, upload}
      _ -> :error
    end
  end
end
