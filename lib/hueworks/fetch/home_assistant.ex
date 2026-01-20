defmodule Hueworks.Fetch.HomeAssistant do
  @moduledoc false

  def fetch do
    Hueworks.Legacy.Fetch.HomeAssistant.fetch()
  end

  def fetch_for_bridge(bridge) do
    Hueworks.Legacy.Fetch.HomeAssistant.fetch_for_bridge(bridge)
  end
end
