defmodule Hueworks.Fetch.Caseta do
  @moduledoc false

  def fetch do
    Hueworks.Legacy.Fetch.Caseta.fetch()
  end

  def fetch_for_bridge(bridge) do
    Hueworks.Legacy.Fetch.Caseta.fetch_for_bridge(bridge)
  end
end
