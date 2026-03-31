defmodule HueworksWeb.LightsLive.Entities do
  @moduledoc false

  alias Hueworks.Groups
  alias Hueworks.Lights

  def fetch("light", id), do: fetch_light(id)
  def fetch("group", id), do: fetch_group(id)
  def fetch(_type, _id), do: {:error, :invalid_type}

  def fetch_light(id) do
    with {:ok, light_id} <- parse_id(id),
         %{} = light <- Lights.get_light(light_id) do
      {:ok, light}
    else
      :error -> {:error, :invalid_id}
      nil -> {:error, :not_found}
    end
  end

  def fetch_group(id) do
    with {:ok, group_id} <- parse_id(id),
         %{} = group <- Groups.get_group(group_id) do
      {:ok, group}
    else
      :error -> {:error, :invalid_id}
      nil -> {:error, :not_found}
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error
end
