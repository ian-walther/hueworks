defmodule HueworksWeb.ConfigLive do
  use Phoenix.LiveView

  alias Hueworks.Bridges
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def mount(_params, _session, socket) do
    {:ok, assign(socket, bridges: list_bridges())}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_entities", %{"id" => id}, socket) do
    case Repo.get(Bridge, id) do
      nil ->
        {:noreply, socket}

      bridge ->
        {:ok, _} = Bridges.delete_entities(bridge)
        {:noreply, assign(socket, bridges: list_bridges())}
    end
  end

  def handle_event("delete_bridge", %{"id" => id}, socket) do
    case Repo.get(Bridge, id) do
      nil ->
        {:noreply, socket}

      bridge ->
        {:ok, _} = Bridges.delete_bridge(bridge)
        {:noreply, assign(socket, bridges: list_bridges())}
    end
  end

  defp list_bridges do
    Repo.all(Bridge)
  end
end
