defmodule Hueworks.Import.Fetch.Common do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def load_enabled_bridges(type) do
    Repo.all(from(b in Bridge, where: b.type == ^type and b.enabled == true))
  end

  def load_enabled_bridge!(type) do
    case load_enabled_bridges(type) do
      [bridge] ->
        bridge

      [] ->
        raise "No enabled #{type} bridge found. Seed bridges before fetching."

      _ ->
        raise "Multiple enabled #{type} bridges found. Only one is supported for now."
    end
  end

  def invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end
end
