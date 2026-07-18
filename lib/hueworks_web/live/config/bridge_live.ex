defmodule HueworksWeb.BridgeLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.Bridges
  alias Hueworks.Credentials
  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Import.Source
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  def mount(params, _session, socket) do
    ha_export_mqtt = ha_export_mqtt_connection()
    type = initial_type(params)

    socket =
      socket
      |> assign(
        mode: :new,
        host: "",
        type: type,
        hue_setup_mode: :guided,
        hue_api_key: "",
        hue_discovery_status: :idle,
        hue_discovery_error: nil,
        hue_discoveries: [],
        hue_discovery_request_id: nil,
        hue_pair_status: :idle,
        hue_pair_error: nil,
        hue_pair_host: nil,
        hue_pair_request_id: nil,
        ha_setup_mode: :guided,
        ha_token: "",
        ha_external_id: nil,
        ha_discovery_status: :idle,
        ha_discovery_error: nil,
        ha_discoveries: [],
        ha_discovery_request_id: nil,
        z2m_broker_port: "1883",
        z2m_username: "",
        z2m_password: "",
        z2m_base_topic: "zigbee2mqtt",
        ha_export_mqtt: ha_export_mqtt,
        ha_import_order_risk: Bridges.ha_import_order_risk(),
        caseta_cert_path: "",
        caseta_key_path: "",
        caseta_cacert_path: "",
        caseta_staged_paths: %{},
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil,
        test_request_id: nil
      )
      |> allow_upload(:caseta_cert, accept: ~w(.crt), max_entries: 1, auto_upload: true)
      |> allow_upload(:caseta_key, accept: ~w(.key), max_entries: 1, auto_upload: true)
      |> allow_upload(:caseta_cacert, accept: ~w(.crt), max_entries: 1, auto_upload: true)

    socket = if connected?(socket), do: start_initial_discovery(socket), else: socket

    {:ok, socket}
  end

  defp initial_type(%{"type" => type}) when type in ["hue", "ha", "caseta", "z2m"], do: type
  defp initial_type(_params), do: "hue"

  defp start_initial_discovery(%{assigns: %{type: "hue"}} = socket),
    do: start_hue_discovery(socket)

  defp start_initial_discovery(%{assigns: %{type: "ha"}} = socket),
    do: start_ha_discovery(socket)

  defp start_initial_discovery(socket), do: socket

  def handle_event("update_bridge", %{"type" => "hue"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))
    clear_caseta_staged_paths(socket)

    {:noreply,
     assign(socket,
       host: host,
       type: Map.get(params, "type", socket.assigns.type),
       hue_api_key: Map.get(params, "hue_api_key", socket.assigns.hue_api_key),
       caseta_staged_paths: %{},
       test_status: :idle,
       test_error: nil,
       test_bridge_name: nil,
       test_request_id: nil
     )}
  end

  def handle_event("discover_hue_bridges", _params, socket) do
    {:noreply, start_hue_discovery(socket)}
  end

  def handle_event("show_manual_hue", _params, socket) do
    {:noreply,
     assign(socket,
       hue_setup_mode: :manual,
       hue_pair_status: :idle,
       hue_pair_error: nil,
       hue_pair_request_id: nil
     )}
  end

  def handle_event("show_guided_hue", _params, socket) do
    socket =
      assign(socket,
        hue_setup_mode: :guided,
        test_status: :idle,
        test_error: nil,
        test_request_id: nil
      )

    socket =
      if socket.assigns.hue_discovery_status in [:idle, :error] do
        start_hue_discovery(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event(
        "pair_hue_bridge",
        %{"host" => host, "external_id" => external_id},
        socket
      ) do
    pair_hue_bridge(socket, host, external_id)
  end

  def handle_event("cancel_hue_pairing", _params, socket) do
    {:noreply,
     assign(socket,
       hue_pair_status: :idle,
       hue_pair_error: nil,
       hue_pair_host: nil,
       hue_pair_request_id: nil
     )}
  end

  def handle_event("update_bridge", %{"type" => "ha"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))
    clear_caseta_staged_paths(socket)

    socket =
      assign(socket,
        host: host,
        type: Map.get(params, "type", socket.assigns.type),
        ha_token: Map.get(params, "ha_token", socket.assigns.ha_token),
        caseta_staged_paths: %{},
        test_status: :idle,
        test_error: nil,
        test_bridge_name: nil,
        test_request_id: nil
      )

    socket =
      if socket.assigns.ha_discovery_status == :idle do
        start_ha_discovery(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("discover_ha_instances", _params, socket) do
    {:noreply, start_ha_discovery(socket)}
  end

  def handle_event("select_ha_instance", %{"host" => host, "external_id" => external_id}, socket) do
    case find_selectable_ha(socket.assigns.ha_discoveries, host, external_id) do
      nil ->
        {:noreply,
         assign(socket,
           ha_discovery_error: "Rediscover Home Assistant before selecting that instance."
         )}

      %{device: device} ->
        {:noreply,
         assign(socket,
           host: Hueworks.BridgeOnboarding.HomeAssistant.Device.endpoint(device),
           ha_external_id: device.id,
           ha_discovery_error: nil,
           test_status: :idle,
           test_error: nil
         )}
    end
  end

  def handle_event("show_manual_ha", _params, socket) do
    {:noreply,
     assign(socket,
       ha_setup_mode: :manual,
       host: "",
       ha_external_id: nil,
       ha_discovery_error: nil,
       test_status: :idle,
       test_error: nil
     )}
  end

  def handle_event("show_guided_ha", _params, socket) do
    socket =
      assign(socket,
        ha_setup_mode: :guided,
        host: "",
        ha_external_id: nil,
        ha_token: "",
        test_status: :idle,
        test_error: nil
      )

    {:noreply, start_ha_discovery(socket)}
  end

  def handle_event("update_bridge", %{"type" => "caseta"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))

    {:noreply,
     assign(socket,
       host: host,
       type: Map.get(params, "type", socket.assigns.type),
       caseta_cert_path: Map.get(params, "caseta_cert_path", socket.assigns.caseta_cert_path),
       caseta_key_path: Map.get(params, "caseta_key_path", socket.assigns.caseta_key_path),
       caseta_cacert_path:
         Map.get(params, "caseta_cacert_path", socket.assigns.caseta_cacert_path),
       test_status: :idle,
       test_error: nil,
       test_bridge_name: nil,
       test_request_id: nil
     )}
  end

  def handle_event("update_bridge", %{"type" => "z2m"} = params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))
    clear_caseta_staged_paths(socket)

    {:noreply,
     assign(socket,
       host: host,
       type: Map.get(params, "type", socket.assigns.type),
       z2m_broker_port: Map.get(params, "z2m_broker_port", socket.assigns.z2m_broker_port),
       z2m_username: Map.get(params, "z2m_username", socket.assigns.z2m_username),
       z2m_password: Map.get(params, "z2m_password", socket.assigns.z2m_password),
       z2m_base_topic: Map.get(params, "z2m_base_topic", socket.assigns.z2m_base_topic),
       caseta_staged_paths: %{},
       test_status: :idle,
       test_error: nil,
       test_bridge_name: nil,
       test_request_id: nil
     )}
  end

  def handle_event("use_ha_export_mqtt", _params, socket) do
    case socket.assigns.ha_export_mqtt do
      %{host: host, port: port, username: username, password: password} ->
        {:noreply,
         socket
         |> assign(
           host: host,
           z2m_broker_port: Integer.to_string(port),
           z2m_username: username || "",
           z2m_password: password || "",
           test_status: :idle,
           test_error: nil,
           test_bridge_name: nil,
           test_request_id: nil
         )
         |> put_flash(
           :info,
           "Copied the existing MQTT connection. Confirm the Zigbee2MQTT base topic, then test it."
         )}

      nil ->
        {:noreply,
         put_flash(socket, :error, "Configure Home Assistant MQTT export before reusing it here.")}
    end
  end

  def handle_event("update_bridge", params, socket) do
    host = Util.normalize_host_input(Map.get(params, "host", socket.assigns.host))
    clear_caseta_staged_paths(socket)

    {:noreply,
     assign(socket,
       host: host,
       type: Map.get(params, "type", socket.assigns.type),
       caseta_staged_paths: %{},
       test_status: :idle,
       test_error: nil,
       test_bridge_name: nil,
       test_request_id: nil
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

  def handle_async({:test_bridge, request_id}, {:ok, result}, socket) do
    if socket.assigns.test_request_id == request_id do
      {:noreply, apply_test_result(socket, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:discover_hue, request_id}, {:ok, result}, socket) do
    if socket.assigns.hue_discovery_request_id == request_id do
      case result do
        {:ok, devices} ->
          {:noreply,
           assign(socket,
             hue_discovery_status: :ok,
             hue_discovery_error: nil,
             hue_discoveries: decorate_hue_devices(devices),
             hue_discovery_request_id: nil
           )}

        {:error, message} ->
          {:noreply,
           assign(socket,
             hue_discovery_status: :error,
             hue_discovery_error: message,
             hue_discoveries: [],
             hue_discovery_request_id: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:discover_ha, request_id}, {:ok, result}, socket) do
    if socket.assigns.ha_discovery_request_id == request_id do
      case result do
        {:ok, devices} ->
          {:noreply,
           assign(socket,
             ha_discovery_status: :ok,
             ha_discovery_error: nil,
             ha_discoveries: decorate_ha_devices(devices),
             ha_discovery_request_id: nil
           )}

        {:error, message} ->
          {:noreply,
           assign(socket,
             ha_discovery_status: :error,
             ha_discovery_error: message,
             ha_discoveries: [],
             ha_discovery_request_id: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:discover_ha, request_id}, {:exit, _reason}, socket) do
    if socket.assigns.ha_discovery_request_id == request_id do
      {:noreply,
       assign(socket,
         ha_discovery_status: :error,
         ha_discovery_error:
           "Home Assistant discovery stopped unexpectedly. Retry or use the manual address fallback.",
         ha_discoveries: [],
         ha_discovery_request_id: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:discover_hue, request_id}, {:exit, _reason}, socket) do
    if socket.assigns.hue_discovery_request_id == request_id do
      {:noreply,
       assign(socket,
         hue_discovery_status: :error,
         hue_discovery_error:
           "Hue discovery stopped unexpectedly. Retry or use the manual address fallback.",
         hue_discoveries: [],
         hue_discovery_request_id: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:pair_hue, request_id}, {:ok, result}, socket) do
    if socket.assigns.hue_pair_request_id == request_id do
      case result do
        {:ok, pairing} ->
          save_paired_hue(socket, pairing)

        {:error, message} ->
          {:noreply,
           assign(socket,
             hue_pair_status: :error,
             hue_pair_error: message,
             hue_pair_request_id: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:pair_hue, request_id}, {:exit, _reason}, socket) do
    if socket.assigns.hue_pair_request_id == request_id do
      {:noreply,
       assign(socket,
         hue_pair_status: :error,
         hue_pair_error: "Hue pairing stopped unexpectedly. Press the link button and retry.",
         hue_pair_request_id: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:test_bridge, request_id}, {:exit, reason}, socket) do
    if socket.assigns.test_request_id == request_id do
      {:noreply,
       assign(socket,
         test_status: :error,
         test_error: "Connection test crashed: #{inspect(reason)}",
         test_request_id: nil
       )}
    else
      {:noreply, socket}
    end
  end

  defp save_bridge(socket) do
    case Source.normalize(socket.assigns.type) do
      nil ->
        {:noreply, assign(socket, test_status: :error, test_error: "Unsupported bridge type.")}

      type ->
        credentials = build_credentials(socket)
        name = socket.assigns.test_bridge_name || Util.default_bridge_name(socket.assigns.type)

        changeset =
          Bridge.changeset(%Bridge{}, %{
            type: type,
            name: name,
            host: socket.assigns.host,
            external_id: bridge_external_id(socket),
            credentials: credentials,
            enabled: true,
            import_complete: false
          })

        case Repo.insert(changeset) do
          {:ok, bridge} ->
            {:noreply, push_navigate(socket, to: "/config/bridges/#{bridge.id}/import")}

          {:error, changeset} ->
            {:noreply,
             assign(socket,
               test_status: :error,
               test_error: Util.format_changeset_error(changeset)
             )}
        end
    end
  end

  defp save_paired_hue(socket, pairing) do
    changeset =
      Bridge.changeset(%Bridge{}, %{
        type: :hue,
        name: pairing.name,
        host: socket.assigns.hue_pair_host,
        external_id: pairing.external_id,
        credentials: %{"api_key" => pairing.api_key},
        enabled: true,
        import_complete: false
      })

    case Repo.insert(changeset) do
      {:ok, bridge} ->
        {:noreply, push_navigate(socket, to: "/config/bridges/#{bridge.id}/import")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           hue_pair_status: :error,
           hue_pair_error: paired_hue_save_error(changeset),
           hue_pair_request_id: nil
         )}
    end
  end

  defp test_bridge(socket) do
    run_bridge_test(socket)
  end

  defp pair_hue_bridge(socket, host, external_id) do
    case find_pairable_hue(socket.assigns.hue_discoveries, host, external_id) do
      nil ->
        {:noreply,
         assign(socket,
           hue_pair_status: :error,
           hue_pair_error: "Rediscover Hue bridges before trying to pair."
         )}

      %{device: device} ->
        request_id = System.unique_integer([:positive])

        socket =
          assign(socket,
            hue_pair_status: :pairing,
            hue_pair_error: nil,
            hue_pair_host: device.host,
            hue_pair_request_id: request_id
          )

        {:noreply,
         start_async(socket, {:pair_hue, request_id}, fn ->
           hue_onboarding_module().pair(device.host, device.id)
         end)}
    end
  end

  defp run_bridge_test(socket) do
    case build_connection_request(socket) do
      {:ok, socket, request} ->
        request_id = System.unique_integer([:positive])

        socket =
          assign(socket,
            test_status: :testing,
            test_error: nil,
            test_bridge_name: nil,
            test_request_id: request_id
          )

        {:noreply,
         start_async(socket, {:test_bridge, request_id}, fn ->
           run_connection_test(request)
         end)}

      {:error, message} ->
        {:noreply, assign(socket, test_status: :error, test_error: message)}
    end
  end

  defp build_connection_request(%{assigns: %{type: "hue"}} = socket) do
    {:ok, socket,
     %{
       type: :hue,
       host: socket.assigns.host,
       api_key: socket.assigns.hue_api_key
     }}
  end

  defp build_connection_request(%{assigns: %{type: "ha"}} = socket) do
    {:ok, socket,
     %{
       type: :ha,
       host: socket.assigns.host,
       token: socket.assigns.ha_token
     }}
  end

  defp build_connection_request(%{assigns: %{type: "caseta"}} = socket) do
    case stage_caseta_uploads(socket) do
      {:ok, socket, staged} ->
        {:ok, assign(socket, caseta_staged_paths: staged),
         %{type: :caseta, host: socket.assigns.host, staged: staged}}

      {:error, message} ->
        {:error, message}
    end
  end

  defp build_connection_request(%{assigns: %{type: "z2m"}} = socket) do
    {:ok, socket,
     %{
       type: :z2m,
       host: socket.assigns.host,
       opts: %{
         "broker_port" => socket.assigns.z2m_broker_port,
         "username" => socket.assigns.z2m_username,
         "password" => socket.assigns.z2m_password,
         "base_topic" => socket.assigns.z2m_base_topic
       }
     }}
  end

  defp build_connection_request(_socket), do: {:error, "Missing required fields."}

  defp run_connection_test(%{type: :hue, host: host, api_key: api_key}) do
    connection_test_module(:hue).test(host, api_key)
  end

  defp run_connection_test(%{type: :ha, host: host, token: token}) do
    connection_test_module(:ha).test(host, token)
  end

  defp run_connection_test(%{type: :caseta, host: host, staged: staged}) do
    connection_test_module(:caseta).test(host, staged)
  end

  defp run_connection_test(%{type: :z2m, host: host, opts: opts}) do
    connection_test_module(:z2m).test(host, opts)
  end

  defp apply_test_result(socket, result) do
    case result do
      {:ok, name} ->
        assign(socket,
          test_status: :ok,
          test_error: nil,
          test_bridge_name: name,
          test_request_id: nil
        )

      :ok ->
        assign(socket,
          test_status: :ok,
          test_error: nil,
          test_bridge_name: nil,
          test_request_id: nil
        )

      {:error, message} ->
        assign(socket, test_status: :error, test_error: message, test_request_id: nil)
    end
  end

  defp connection_test_module(type) do
    Application.get_env(:hueworks, :connection_test_modules, %{})
    |> Map.get(type, default_connection_test_module(type))
  end

  defp start_hue_discovery(socket) do
    request_id = System.unique_integer([:positive])

    socket
    |> assign(
      hue_setup_mode: :guided,
      hue_discovery_status: :searching,
      hue_discovery_error: nil,
      hue_discoveries: [],
      hue_discovery_request_id: request_id,
      hue_pair_status: :idle,
      hue_pair_error: nil,
      hue_pair_host: nil,
      hue_pair_request_id: nil
    )
    |> start_async({:discover_hue, request_id}, fn -> hue_onboarding_module().discover() end)
  end

  defp hue_onboarding_module do
    Application.get_env(:hueworks, :hue_onboarding_module, Hueworks.BridgeOnboarding.Hue)
  end

  defp start_ha_discovery(socket) do
    request_id = System.unique_integer([:positive])

    socket
    |> assign(
      ha_setup_mode: :guided,
      ha_discovery_status: :searching,
      ha_discovery_error: nil,
      ha_discoveries: [],
      ha_discovery_request_id: request_id
    )
    |> start_async({:discover_ha, request_id}, fn -> ha_onboarding_module().discover() end)
  end

  defp ha_onboarding_module do
    Application.get_env(
      :hueworks,
      :ha_onboarding_module,
      Hueworks.BridgeOnboarding.HomeAssistant
    )
  end

  defp decorate_hue_devices(devices) do
    configured = Bridges.list_bridges()

    Enum.map(devices, fn device ->
      existing =
        Enum.find(configured, fn bridge ->
          bridge.type == :hue and
            ((is_binary(device.id) and bridge.external_id == device.id) or
               bridge.host == device.host)
        end)

      %{device: device, configured?: not is_nil(existing), existing: existing}
    end)
  end

  defp find_pairable_hue(discoveries, host, external_id) do
    external_id = empty_to_nil(external_id)

    Enum.find(discoveries, fn discovery ->
      discovery.configured? == false and discovery.device.host == host and
        discovery.device.id == external_id
    end)
  end

  defp decorate_ha_devices(devices) do
    configured = Bridges.list_bridges()

    Enum.map(devices, fn device ->
      endpoint = Hueworks.BridgeOnboarding.HomeAssistant.Device.endpoint(device)

      existing =
        Enum.find(configured, fn bridge ->
          bridge.type == :ha and
            ((is_binary(device.id) and bridge.external_id == device.id) or bridge.host == endpoint)
        end)

      %{device: device, configured?: not is_nil(existing), existing: existing}
    end)
  end

  defp find_selectable_ha(discoveries, host, external_id) do
    external_id = empty_to_nil(external_id)

    Enum.find(discoveries, fn discovery ->
      discovery.configured? == false and
        Hueworks.BridgeOnboarding.HomeAssistant.Device.endpoint(discovery.device) == host and
        discovery.device.id == external_id
    end)
  end

  defp paired_hue_save_error(changeset) do
    errors = Util.format_changeset_error(changeset)

    if String.contains?(errors, "has already been taken") do
      "That Hue bridge is already configured. Rediscover bridges to refresh this page."
    else
      errors
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp bridge_external_id(%{assigns: %{type: "ha", ha_external_id: external_id}}),
    do: external_id

  defp bridge_external_id(_socket), do: nil

  defp default_connection_test_module(:hue), do: Hueworks.ConnectionTest.Hue
  defp default_connection_test_module(:ha), do: Hueworks.ConnectionTest.HomeAssistant
  defp default_connection_test_module(:caseta), do: Hueworks.ConnectionTest.Caseta
  defp default_connection_test_module(:z2m), do: Hueworks.ConnectionTest.Z2M

  defp ha_export_mqtt_connection do
    settings = AppSettings.global_map()

    case settings.ha_export_mqtt_host do
      host when is_binary(host) and host != "" ->
        %{
          host: host,
          port: settings.ha_export_mqtt_port,
          username: settings.ha_export_mqtt_username,
          password: settings.ha_export_mqtt_password
        }

      _ ->
        nil
    end
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

  defp validate_required_fields(%{assigns: %{type: "z2m"}} = socket) do
    missing =
      []
      |> maybe_missing(socket.assigns.host == "", "host")
      |> maybe_missing(
        not Z2MConfig.valid_port?(socket.assigns.z2m_broker_port),
        "z2m_broker_port"
      )
      |> maybe_missing(String.trim(socket.assigns.z2m_base_topic) == "", "z2m_base_topic")

    missing_message(missing)
  end

  defp validate_required_fields(_socket), do: {:error, "Missing required fields."}

  defp missing_message([]), do: :ok

  defp missing_message(missing),
    do: {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}

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
    if caseta_upload_entries?(socket) do
      restage_caseta_uploads(socket)
    else
      {:ok, socket, staged}
    end
  end

  defp stage_caseta_uploads(socket), do: restage_caseta_uploads(socket)

  defp restage_caseta_uploads(socket) do
    host_prefix = Util.host_prefix(socket.assigns.host)
    dir = Credentials.caseta_staging_dir()
    File.mkdir_p!(dir)
    Credentials.prune_stale_caseta_staging_files()
    clear_caseta_staged_paths(socket)
    stamp = System.unique_integer([:positive])

    with :ok <- validate_uploads_complete(socket),
         {:ok, cert_path} <-
           stage_upload(socket, :caseta_cert, dir, "#{host_prefix}_cert_#{stamp}"),
         {:ok, key_path} <- stage_upload(socket, :caseta_key, dir, "#{host_prefix}_key_#{stamp}"),
         {:ok, cacert_path} <-
           stage_upload(socket, :caseta_cacert, dir, "#{host_prefix}_cacert_#{stamp}") do
      {:ok, socket, %{caseta_cert: cert_path, caseta_key: key_path, caseta_cacert: cacert_path}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp caseta_upload_entries?(socket) do
    [:caseta_cert, :caseta_key, :caseta_cacert]
    |> Enum.any?(fn key ->
      socket.assigns.uploads
      |> Map.fetch!(key)
      |> Map.get(:entries)
      |> Kernel.!=([])
    end)
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

  defp build_credentials(%{assigns: %{type: "z2m"}} = socket) do
    %{
      "broker_port" => Z2MConfig.normalize_port(socket.assigns.z2m_broker_port),
      "username" => Z2MConfig.normalize_optional(socket.assigns.z2m_username),
      "password" => Z2MConfig.normalize_optional(socket.assigns.z2m_password),
      "base_topic" => Z2MConfig.normalize_base_topic(socket.assigns.z2m_base_topic)
    }
  end

  defp build_credentials(_socket), do: %{}

  defp save_caseta_uploads(host, staged) do
    host_prefix = Util.host_prefix(host)
    dir = Credentials.caseta_dir()
    File.mkdir_p!(dir)

    %{
      "cert_path" => move_upload(staged.caseta_cert, Path.join(dir, "#{host_prefix}_cert.crt")),
      "key_path" => move_upload(staged.caseta_key, Path.join(dir, "#{host_prefix}_key.key")),
      "cacert_path" =>
        move_upload(staged.caseta_cacert, Path.join(dir, "#{host_prefix}_cacert.crt"))
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

  defp clear_caseta_staged_paths(%{assigns: %{caseta_staged_paths: staged}}) do
    staged
    |> Map.values()
    |> Credentials.delete_paths()
  end

  defp clear_caseta_staged_paths(_socket), do: :ok
end
