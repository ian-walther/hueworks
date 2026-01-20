defmodule Hueworks.Fetch.Hue do
  @moduledoc false

  def fetch do
    Hueworks.Legacy.Fetch.Hue.fetch()
  end

  def fetch_for_bridge(bridge) do
    Hueworks.Legacy.Fetch.Hue.fetch_for_bridge(bridge)
  end
end
