defmodule HueworksWeb.BridgesConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.Bridges
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  def mount(_params, _session, socket) do
    {:ok, assign(socket, bridge_entries: list_bridge_entries())}
  end

  def handle_event("delete_entities", %{"id" => id}, socket) do
    case Bridges.get_bridge(id) do
      nil ->
        {:noreply, socket}

      bridge ->
        case Bridges.delete_entities(bridge) do
          {:ok, _result} ->
            {:noreply, assign(socket, bridge_entries: list_bridge_entries())}

          {:error, reason} ->
            {:noreply,
             put_notice(
               socket,
               :error,
               "Could not delete entities: #{Util.format_reason(reason)}"
             )}
        end
    end
  end

  def handle_event("delete_bridge", %{"id" => id}, socket) do
    case Bridges.get_bridge(id) do
      nil ->
        {:noreply, socket}

      bridge ->
        case Bridges.delete_bridge(bridge) do
          {:ok, _deleted_bridge} ->
            {:noreply, assign(socket, bridge_entries: list_bridge_entries())}

          {:error, reason} ->
            {:noreply,
             put_notice(socket, :error, "Could not delete bridge: #{Util.format_reason(reason)}")}
        end
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
