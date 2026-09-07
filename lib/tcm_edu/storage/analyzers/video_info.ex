defmodule TcmEdu.Storage.Analyzers.VideoInfo do
  @moduledoc """
  Analyzer that extracts metadata from MP4 video files using ffprobe.

  Returns: duration (seconds), width, height, codec, bitrate, frame_rate
  """

  @behaviour AshStorage.Analyzer

  @impl true
  def accept?("video/" <> _), do: true
  def accept?(_), do: false

  @impl true
  def analyze(path, _opts) do
    case System.cmd("ffprobe", [
           "-v", "quiet",
           "-print_format", "json",
           "-show_format",
           "-show_streams",
           path
         ]) do
      {output, 0} ->
        data = Jason.decode!(output)

        video_stream =
          (data["streams"] || [])
          |> Enum.find(&(&1["codec_type"] == "video"))

        audio_stream =
          (data["streams"] || [])
          |> Enum.find(&(&1["codec_type"] == "audio"))

        format = data["format"] || %{}
        duration = parse_float(format["duration"])
        bitrate = parse_integer(format["bit_rate"])

        metadata = %{
          "duration_seconds" => duration,
          "duration_display" => format_duration(duration),
          "width" => parse_integer(video_stream["width"]),
          "height" => parse_integer(video_stream["height"]),
          "video_codec" => video_stream["codec_name"],
          "audio_codec" => audio_stream["codec_name"],
          "frame_rate" => video_stream["r_frame_rate"],
          "bitrate" => bitrate,
          "bitrate_display" => if(bitrate, do: "#{div(bitrate, 1000)} kbps"),
          "file_size_bytes" => parse_integer(format["size"]),
          "format_name" => format["format_name"]
        }

        {:ok, metadata}

      {error, _} ->
        {:error, "ffprobe failed: #{error}"}
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(s) when is_binary(s), do: String.to_float(s)
  defp parse_float(f) when is_float(f), do: f
  defp parse_float(i) when is_integer(i), do: i * 1.0

  defp parse_integer(nil), do: nil
  defp parse_integer(s) when is_binary(s), do: String.to_integer(s)
  defp parse_integer(i) when is_integer(i), do: i

  defp format_duration(nil), do: nil

  defp format_duration(secs) when is_float(secs) or is_integer(secs) do
    total = round(secs)
    hours = div(total, 3600)
    minutes = div(rem(total, 3600), 60)
    secs_left = rem(total, 60)
    pad = fn v -> String.pad_leading(Integer.to_string(v), 2, "0") end

    if hours > 0 do
      "#{pad.(hours)}h #{pad.(minutes)}m #{pad.(secs_left)}s"
    else
      "#{pad.(minutes)}m #{pad.(secs_left)}s"
    end
  end
end
