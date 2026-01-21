defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.ImportPipeline

  def mount(%{"id" => id}, _session, socket) do
    bridge = Repo.get!(Bridge, id)

    {:ok,
     assign(socket,
       bridge: bridge,
       bridge_import: nil,
       import_status: :idle,
       import_error: nil,
       import_blob: nil
     )}
  end

  def handle_event("import_configuration", _params, socket) do
    case ImportPipeline.create_import(socket.assigns.bridge) do
      {:ok, bridge_import} ->
        {:noreply,
         assign(socket,
           import_status: :ok,
           import_error: nil,
           import_blob: bridge_import.raw_blob,
           bridge_import: bridge_import
         )}

      {:error, message} ->
        {:noreply, assign(socket, import_status: :error, import_error: message)}
    end
  end
end
