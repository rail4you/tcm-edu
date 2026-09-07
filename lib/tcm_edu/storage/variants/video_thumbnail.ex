defmodule TcmEdu.Storage.Variants.VideoThumbnail do
  @moduledoc """
  Variant that extracts a thumbnail image from a video using ffmpeg.

  Captures the frame at the given `second` (default: 1) and outputs a JPEG image.

  ## Options

    * `:second` — which second to capture (default: 1)
    * `:width` — max width in pixels (default: nil, keeps original ratio)
  """

  @behaviour AshStorage.Variant

  @impl true
  def accept?("video/" <> _), do: true
  def accept?(_), do: false

  @impl true
  def transform(source_path, dest_path, opts) do
    second = Keyword.get(opts, :second, 1)
    width = Keyword.get(opts, :width)

    # Add .jpg extension so ffmpeg knows the output format
    jpg_path = dest_path <> ".jpg"

    args =
      [
        "-y",
        "-ss", "#{second}",
        "-i", source_path,
        "-vframes", "1",
        "-q:v", "2"
      ] ++
        if width do
          ["-vf", "scale='min(#{width},iw)':min'(#{div(width * 9, 16)},ih)':force_original_aspect_ratio=decrease"]
        else
          []
        end ++
        [jpg_path]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        # Copy to the expected dest_path
        File.cp!(jpg_path, dest_path)
        File.rm!(jpg_path)
        {:ok, %{content_type: "image/jpeg"}}

      {error, _} ->
        {:error, "ffmpeg failed: #{error}"}
    end
  end
end
