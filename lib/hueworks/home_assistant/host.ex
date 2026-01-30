defmodule Hueworks.HomeAssistant.Host do
  @moduledoc false

  def normalize(host) when is_binary(host) do
    trimmed = String.trim(host)

    cond do
      trimmed == "" ->
        "127.0.0.1:8123"

      String.contains?(trimmed, ":") ->
        trimmed

      true ->
        "#{trimmed}:8123"
    end
  end

  def normalize(_host), do: "127.0.0.1:8123"
end
