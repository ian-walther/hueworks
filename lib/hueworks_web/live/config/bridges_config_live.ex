defmodule HueworksWeb.BridgesConfigLive do
  use Phoenix.LiveView

  alias Hueworks.Bridges

  def mount(_params, _session, socket) do
    {:ok, assign(socket, bridge_entries: list_bridge_entries())}
  end

  def handle_event("delete_entities", %{"id" => id}, socket) do
    case Bridges.get_bridge(id) do
      nil ->
        {:noreply, socket}

      bridge ->
        {:ok, _} = Bridges.delete_entities(bridge)
        {:noreply, assign(socket, bridge_entries: list_bridge_entries())}
    end
  end

  def handle_event("delete_bridge", %{"id" => id}, socket) do
    case Bridges.get_bridge(id) do
      nil ->
        {:noreply, socket}

      bridge ->
        {:ok, _} = Bridges.delete_bridge(bridge)
        {:noreply, assign(socket, bridge_entries: list_bridge_entries())}
    end
  end

  defp list_bridge_entries do
    Bridges.list_bridges()
    |> Enum.map(fn bridge ->
      %{
        bridge: bridge,
        imported?: Bridges.imported?(bridge),
        latest_import: Bridges.latest_import(bridge)
      }
    end)
  end
end
