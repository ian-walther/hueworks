defmodule Hueworks.Instance do
  @moduledoc false

  @default_slug "app"
  @max_slug_length 12

  def name do
    System.get_env("HUEWORKS_INSTANCE_NAME") ||
      Application.get_env(:hueworks, :instance_name) ||
      @default_slug
  end

  def slug do
    name()
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> @default_slug
      value -> String.slice(value, 0, @max_slug_length)
    end
  end

  def z2m_client_id(prefix, bridge_id) do
    "#{prefix}#{bridge_id}-#{slug()}"
  end
end
