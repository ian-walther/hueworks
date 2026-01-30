defmodule HueworksWeb.BridgeLive do
  use Phoenix.LiveView

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        mode: :new,
        host: "",
        type: "hue",
        hue_api_key: "",
        ha_token: "",
        caseta_cert_path: "",
        caseta_key_path: "",
        caseta_cacert_path: "",
        caseta_staged_paths: %{},
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil
      )
      |> allow_upload(:caseta_cert, accept: ~w(.crt), max_entries: 1, auto_upload: true)
      |> allow_upload(:caseta_key, accept: ~w(.key), max_entries: 1, auto_upload: true)
      |> allow_upload(:caseta_cacert, accept: ~w(.crt), max_entries: 1, auto_upload: true)

    {:ok, socket}
  end

  def handle_event("update_bridge", %{"type" => "hue"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))

    {:noreply,
      assign(socket,
        host: host,
        type: Map.get(params, "type", socket.assigns.type),
        hue_api_key: Map.get(params, "hue_api_key", socket.assigns.hue_api_key),
        caseta_staged_paths: %{},
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil
      )}
  end

  def handle_event("update_bridge", %{"type" => "ha"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))

    {:noreply,
      assign(socket,
        host: host,
        type: Map.get(params, "type", socket.assigns.type),
        ha_token: Map.get(params, "ha_token", socket.assigns.ha_token),
        caseta_staged_paths: %{},
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil
      )}
  end

  def handle_event("update_bridge", %{"type" => "caseta"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))

    {:noreply,
      assign(socket,
        host: host,
        type: Map.get(params, "type", socket.assigns.type),
        caseta_cert_path: Map.get(params, "caseta_cert_path", socket.assigns.caseta_cert_path),
        caseta_key_path: Map.get(params, "caseta_key_path", socket.assigns.caseta_key_path),
        caseta_cacert_path: Map.get(params, "caseta_cacert_path", socket.assigns.caseta_cacert_path),
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil
      )}
  end

  def handle_event("update_bridge", params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))

    {:noreply,
      assign(socket,
        host: host,
        type: Map.get(params, "type", socket.assigns.type),
        caseta_staged_paths: %{},
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil
      )}
  end

  def handle_event("test_bridge", _params, socket) do
    case validate_required_fields(socket) do
      :ok ->
        test_bridge(socket)

      {:error, message} ->
        {:noreply, assign(socket, test_status: :error, test_error: message)}
    end
  end

  def handle_event("proceed_bridge", _params, socket) do
    if socket.assigns.test_status != :ok do
      {:noreply, assign(socket, test_status: :error, test_error: "Run Test before proceeding.")}
    else
      save_bridge(socket)
    end
  end

  defp save_bridge(socket) do
    credentials = build_credentials(socket)
    name = socket.assigns.test_bridge_name || Util.default_bridge_name(socket.assigns.type)

    changeset =
      Bridge.changeset(%Bridge{}, %{
        type: String.to_atom(socket.assigns.type),
        name: name,
        host: socket.assigns.host,
        credentials: credentials,
        enabled: true,
        import_complete: false
      })

    case Repo.insert(changeset) do
      {:ok, bridge} ->
        {:noreply, push_navigate(socket, to: "/config/bridge/#{bridge.id}/setup")}

      {:error, changeset} ->
        {:noreply, assign(socket, test_status: :error, test_error: Util.format_changeset_error(changeset))}
    end
  end

  defp test_bridge(%{assigns: %{type: "hue"}} = socket) do
    case Hueworks.ConnectionTest.Hue.test(socket.assigns.host, socket.assigns.hue_api_key) do
      {:ok, name} ->
        {:noreply, assign(socket, test_status: :ok, test_error: nil, test_bridge_name: name)}

      :ok ->
        {:noreply, assign(socket, test_status: :ok, test_error: nil, test_bridge_name: nil)}

      {:error, message} ->
        {:noreply, assign(socket, test_status: :error, test_error: message)}
    end
  end

  defp test_bridge(%{assigns: %{type: "ha"}} = socket) do
    case Hueworks.ConnectionTest.HomeAssistant.test(socket.assigns.host, socket.assigns.ha_token) do
      {:ok, name} ->
        {:noreply, assign(socket, test_status: :ok, test_error: nil, test_bridge_name: name)}

      :ok ->
        {:noreply, assign(socket, test_status: :ok, test_error: nil, test_bridge_name: nil)}

      {:error, message} ->
        {:noreply, assign(socket, test_status: :error, test_error: message)}
    end
  end

  defp test_bridge(%{assigns: %{type: "caseta"}} = socket) do
    case stage_caseta_uploads(socket) do
      {:ok, socket, staged} ->
        case Hueworks.ConnectionTest.Caseta.test(socket.assigns.host, staged) do
          {:ok, name} ->
            {:noreply,
             assign(socket,
               caseta_staged_paths: staged,
               test_status: :ok,
               test_error: nil,
               test_bridge_name: name
             )}

          {:error, message} ->
            {:noreply, assign(socket, test_status: :error, test_error: message)}
        end

      {:error, message} ->
        {:noreply, assign(socket, test_status: :error, test_error: message)}
    end
  end

  defp test_bridge(socket) do
    {:noreply, socket}
  end

  defp validate_required_fields(%{assigns: %{type: "hue"}} = socket) do
    missing =
      []
      |> maybe_missing(socket.assigns.host == "", "host")
      |> maybe_missing(socket.assigns.hue_api_key == "", "hue_api_key")

    missing_message(missing)
  end

  defp validate_required_fields(%{assigns: %{type: "ha"}} = socket) do
    missing =
      []
      |> maybe_missing(socket.assigns.host == "", "host")
      |> maybe_missing(socket.assigns.ha_token == "", "ha_token")

    missing_message(missing)
  end

  defp validate_required_fields(%{assigns: %{type: "caseta"}} = socket) do
    missing =
      []
      |> maybe_missing(socket.assigns.host == "", "host")
      |> maybe_missing(caseta_entry_missing?(socket, :caseta_cert), "caseta_cert")
      |> maybe_missing(caseta_entry_missing?(socket, :caseta_key), "caseta_key")
      |> maybe_missing(caseta_entry_missing?(socket, :caseta_cacert), "caseta_cacert")

    missing_message(missing)
  end

  defp validate_required_fields(_socket), do: {:error, "Missing required fields."}

  defp missing_message([]), do: :ok
  defp missing_message(missing), do: {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}

  defp maybe_missing(list, true, label), do: list ++ [label]
  defp maybe_missing(list, false, _label), do: list

  defp caseta_entry_missing?(%{assigns: %{caseta_staged_paths: staged}} = socket, key) do
    case Map.get(staged, key) do
      nil ->
        upload = Map.fetch!(socket.assigns.uploads, key)
        upload.entries == []

      _ ->
        false
    end
  end

  defp stage_caseta_uploads(%{assigns: %{caseta_staged_paths: staged}} = socket)
       when map_size(staged) == 3 do
    {:ok, socket, staged}
  end

  defp stage_caseta_uploads(socket) do
    host_prefix = Util.host_prefix(socket.assigns.host)
    dir = Path.join(["priv", "credentials", "caseta", "staging"])
    File.mkdir_p!(dir)
    stamp = System.unique_integer([:positive])

    with :ok <- validate_uploads_complete(socket),
         {:ok, cert_path} <- stage_upload(socket, :caseta_cert, dir, "#{host_prefix}_cert_#{stamp}"),
         {:ok, key_path} <- stage_upload(socket, :caseta_key, dir, "#{host_prefix}_key_#{stamp}"),
         {:ok, cacert_path} <- stage_upload(socket, :caseta_cacert, dir, "#{host_prefix}_cacert_#{stamp}") do
      {:ok, socket, %{caseta_cert: cert_path, caseta_key: key_path, caseta_cacert: cacert_path}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp stage_upload(socket, upload_name, dir, base) do
    uploads =
      consume_uploaded_entries(socket, upload_name, fn %{path: path}, entry ->
        extension = Path.extname(entry.client_name)
        dest = Path.join(dir, "#{base}#{extension}")
        File.cp!(path, dest)
        {:ok, dest}
      end)

    case uploads do
      [dest | _] -> {:ok, dest}
      [] -> {:error, "Missing required files for Caseta uploads."}
    end
  end

  defp validate_uploads_complete(socket) do
    [:caseta_cert, :caseta_key, :caseta_cacert]
    |> Enum.reduce_while(:ok, fn name, _acc ->
      upload = Map.fetch!(socket.assigns.uploads, name)

      cond do
        upload.errors != [] ->
          {:halt, {:error, "Upload failed for #{name}: #{inspect(upload.errors)}"}}

        upload.entries == [] ->
          {:cont, :ok}

        Enum.any?(upload.entries, fn entry -> entry.done? == false end) ->
          {:halt, {:error, "Uploads in progress. Please wait and try again."}}

        true ->
          {:cont, :ok}
      end
    end)
  end


  defp build_credentials(%{assigns: %{type: "hue", hue_api_key: api_key}}) do
    %{"api_key" => api_key}
  end

  defp build_credentials(%{assigns: %{type: "ha", ha_token: token}}) do
    %{"token" => token}
  end

  defp build_credentials(%{assigns: %{type: "caseta", caseta_staged_paths: staged, host: host}}) do
    save_caseta_uploads(host, staged)
  end

  defp build_credentials(_socket), do: %{}

  defp save_caseta_uploads(host, staged) do
    host_prefix = Util.host_prefix(host)
    dir = Path.join(["priv", "credentials", "caseta"])
    File.mkdir_p!(dir)

    %{
      "cert_path" => move_upload(staged.caseta_cert, Path.join(dir, "#{host_prefix}_cert.crt")),
      "key_path" => move_upload(staged.caseta_key, Path.join(dir, "#{host_prefix}_key.key")),
      "cacert_path" => move_upload(staged.caseta_cacert, Path.join(dir, "#{host_prefix}_cacert.crt"))
    }
  end

  defp move_upload(source, dest) do
    case File.rename(source, dest) do
      :ok ->
        dest

      {:error, _reason} ->
        File.cp!(source, dest)
        File.rm(source)
        dest
    end
  end

end
