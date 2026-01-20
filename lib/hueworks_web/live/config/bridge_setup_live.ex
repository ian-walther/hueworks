defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def mount(%{"id" => id}, _session, socket) do
    bridge = Repo.get!(Bridge, id)

    {:ok,
     assign(socket,
       bridge: bridge,
       import_status: :idle,
       import_error: nil,
       import_blob: nil
     )}
  end

  def handle_event("import_configuration", _params, socket) do
    case import_configuration(socket.assigns.bridge) do
      {:ok, blob} ->
        {:noreply, assign(socket, import_status: :ok, import_error: nil, import_blob: blob)}

      {:error, message} ->
        {:noreply, assign(socket, import_status: :error, import_error: message)}
    end
  end

  defp import_configuration(%Bridge{type: :hue} = bridge) do
    {:ok,
     %{
       fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
       source: :hue,
       data: Hueworks.Fetch.Hue.fetch_for_bridge(bridge)
     }}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp import_configuration(%Bridge{type: :caseta} = bridge) do
    {:ok,
     %{
       fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
       source: :caseta,
       data: Hueworks.Fetch.Caseta.fetch_for_bridge(bridge)
     }}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp import_configuration(%Bridge{type: :ha} = bridge) do
    {:ok,
     %{
       fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
       source: :ha,
       data: Hueworks.Fetch.HomeAssistant.fetch_for_bridge(bridge)
     }}
  rescue
    error -> {:error, Exception.message(error)}
  end
end
