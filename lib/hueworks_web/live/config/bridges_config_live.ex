defmodule HueworksWeb.BridgesConfigLive do
  use Phoenix.LiveView

  alias Hueworks.Bridges
  alias Hueworks.Schemas.Bridge

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
        latest_import: Bridges.latest_import(bridge),
        home_assistant_auth: home_assistant_auth(bridge)
      }
    end)
  end

  defp home_assistant_auth(%Bridge{type: :ha} = bridge) do
    credentials = Bridge.credentials_struct(bridge)

    cond do
      credentials.auth_status == "reauthorization_required" -> :reauthorization_required
      credentials.auth_type == "oauth" -> :oauth
      true -> :manual
    end
  end

  defp home_assistant_auth(_bridge), do: nil
end
