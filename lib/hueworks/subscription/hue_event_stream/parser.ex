defmodule Hueworks.Subscription.HueEventStream.Parser do
  @moduledoc false

  def consume(buffer, chunk) when is_binary(buffer) and is_binary(chunk) do
    {events, rest} = split_events(buffer <> chunk)
    {Enum.flat_map(events, &decode_payload/1), rest}
  end

  defp split_events(buffer) do
    normalized = String.replace(buffer, "\r\n", "\n")
    parts = String.split(normalized, "\n\n")

    case parts do
      [] -> {[], ""}
      [single] -> {[], single}
      _ -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp decode_payload(payload) do
    data =
      payload
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(fn line -> String.trim_leading(line, "data:") |> String.trim() end)
      |> Enum.join("\n")

    if data == "" do
      []
    else
      case Jason.decode(data) do
        {:ok, events} when is_list(events) ->
          Enum.flat_map(events, &unwrap_envelope/1)

        {:ok, event} when is_map(event) ->
          unwrap_envelope(event)

        _ ->
          []
      end
    end
  end

  defp unwrap_envelope(%{"data" => data}) when is_list(data), do: data
  defp unwrap_envelope(event) when is_map(event), do: [event]
  defp unwrap_envelope(_event), do: []
end
