defmodule Hueworks.HomeAssistant.Export do
  @moduledoc false

  use GenServer

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Hueworks.AppSettings
  alias Hueworks.Instance
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Room, Scene}

  @default_port 1883
  @default_discovery_prefix "homeassistant"
  @default_topic_prefix "hueworks/ha_export"

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def reload do
    maybe_cast(:reload)
  end

  def refresh_all_scenes do
    maybe_cast(:refresh_all_scenes)
  end

  def refresh_room(room_id) when is_integer(room_id) do
    maybe_cast({:refresh_room, room_id})
  end

  def refresh_scene(%Scene{id: scene_id}), do: refresh_scene(scene_id)

  def refresh_scene(scene_id) when is_integer(scene_id) do
    maybe_cast({:refresh_scene, scene_id})
  end

  def remove_scene(%Scene{id: scene_id}), do: remove_scene(scene_id)

  def remove_scene(scene_id) when is_integer(scene_id) do
    maybe_cast({:remove_scene, scene_id})
  end

  def client_id do
    "hwhaexp-#{Instance.slug()}"
  end

  def availability_topic, do: "#{@default_topic_prefix}/status"

  def command_topic(scene_id) when is_integer(scene_id),
    do: "#{@default_topic_prefix}/scenes/#{scene_id}/set"

  def attributes_topic(scene_id) when is_integer(scene_id),
    do: "#{@default_topic_prefix}/scenes/#{scene_id}/attributes"

  def discovery_topic(scene_id, discovery_prefix \\ @default_discovery_prefix)
      when is_integer(scene_id) and is_binary(discovery_prefix) do
    "#{discovery_prefix}/scene/hueworks_scene_#{scene_id}/config"
  end

  def command_scene_id(topic_levels, topic_prefix \\ @default_topic_prefix)

  def command_scene_id(topic, topic_prefix) when is_binary(topic) and is_binary(topic_prefix) do
    topic
    |> String.split("/", trim: true)
    |> command_scene_id(topic_prefix)
  end

  def command_scene_id(topic_levels, topic_prefix)
      when is_list(topic_levels) and is_binary(topic_prefix) do
    prefix_levels = String.split("#{topic_prefix}/scenes", "/", trim: true)

    if Enum.take(topic_levels, length(prefix_levels)) == prefix_levels do
      case Enum.drop(topic_levels, length(prefix_levels)) do
        [scene_id, "set"] ->
          case Integer.parse(scene_id) do
            {parsed, ""} -> parsed
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  def command_scene_id(_topic_levels, _topic_prefix), do: nil

  def discovery_payload(%Scene{} = scene, config \\ export_config()) do
    room_name = room_name(scene.room)

    %{
      "platform" => "scene",
      "name" => scene_name(scene),
      "unique_id" => "hueworks_scene_#{scene.id}",
      "command_topic" => command_topic(scene.id),
      "payload_on" => "ON",
      "availability_topic" => availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => attributes_topic(scene.id),
      "device" => %{
        "identifiers" => ["hueworks_room_#{scene.room_id}"],
        "name" => "HueWorks #{room_name}",
        "manufacturer" => "HueWorks",
        "model" => "Room Scenes"
      }
    }
    |> maybe_put("configuration_url", config[:configuration_url])
  end

  def scene_attributes_payload(%Scene{} = scene) do
    %{
      "hueworks_managed" => true,
      "hueworks_scene_id" => scene.id,
      "hueworks_room_id" => scene.room_id,
      "room_name" => room_name(scene.room),
      "scene_name" => scene_name(scene)
    }
  end

  def export_config do
    settings = AppSettings.get_global()

    %{
      enabled: settings.ha_export_enabled == true,
      host: settings.ha_export_mqtt_host,
      port: settings.ha_export_mqtt_port || @default_port,
      username: settings.ha_export_mqtt_username,
      password: settings.ha_export_mqtt_password,
      discovery_prefix: settings.ha_export_discovery_prefix || @default_discovery_prefix
    }
  end

  @impl true
  def init(_state) do
    {:ok, %{config: nil, connection_pid: nil}, {:continue, :configure}}
  end

  @impl true
  def handle_continue(:configure, state) do
    {:noreply, configure(state)}
  end

  @impl true
  def handle_cast(:reload, state) do
    {:noreply, configure(state)}
  end

  def handle_cast(:refresh_all_scenes, state) do
    {:noreply, publish_all_scenes(state)}
  end

  def handle_cast({:refresh_room, room_id}, state) do
    {:noreply, publish_room_scenes(room_id, state)}
  end

  def handle_cast({:refresh_scene, scene_id}, state) do
    {:noreply, publish_scene(scene_id, state)}
  end

  def handle_cast({:remove_scene, scene_id}, state) do
    {:noreply, unpublish_scene(scene_id, state)}
  end

  @impl true
  def handle_info({:mqtt_connected, connection_client_id}, %{config: config} = state) do
    if connection_client_id == client_id() and export_enabled?(config) do
      :ok = publish_availability("online")
      {:noreply, publish_all_scenes(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:mqtt_message, topic_levels, payload}, %{config: config} = state) do
    if export_enabled?(config) do
      case {command_scene_id(topic_levels), normalize_payload(payload)} do
        {scene_id, "ON"} when is_integer(scene_id) ->
          case Scenes.activate_scene(scene_id, trace: %{source: :home_assistant_mqtt_export}) do
            {:ok, _diff, _updated} ->
              :ok

            {:error, reason} ->
              Logger.warning("HA export scene activation failed: #{inspect(reason)}")
          end

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp configure(state) do
    config = export_config()

    cond do
      not export_enabled?(config) ->
        state
        |> publish_availability_if_connected("offline")
        |> stop_connection()
        |> Map.put(:config, config)

      same_config?(state.config, config) and connection_alive?(state.connection_pid) ->
        %{state | config: config}

      true ->
        state
        |> publish_availability_if_connected("offline")
        |> stop_connection()
        |> start_connection(config)
    end
  end

  defp start_connection(state, config) do
    start_opts =
      [
        client_id: client_id(),
        handler: {__MODULE__.Handler, [self(), client_id(), command_topic_filter()]},
        server: {Tortoise.Transport.Tcp, host: String.to_charlist(config.host), port: config.port}
      ]
      |> maybe_put_auth(config)

    case supervisor_module().start_child(start_opts) do
      {:ok, pid} ->
        %{state | config: config, connection_pid: pid}

      {:error, {:already_started, pid}} ->
        %{state | config: config, connection_pid: pid}

      {:error, reason} ->
        Logger.warning(
          "Failed to start Home Assistant export MQTT connection: #{inspect(reason)}"
        )

        %{state | config: config, connection_pid: nil}
    end
  end

  defp stop_connection(%{connection_pid: nil} = state), do: %{state | connection_pid: nil}

  defp stop_connection(%{connection_pid: pid} = state) do
    _ = dynamic_supervisor_module().terminate_child(tortoise_supervisor_name(), pid)
    %{state | connection_pid: nil}
  end

  defp publish_all_scenes(state) do
    if export_enabled?(state.config) do
      list_exportable_scenes()
      |> Enum.each(fn scene ->
        :ok = publish_scene_payloads(scene, state.config)
      end)
    end

    state
  end

  defp publish_room_scenes(room_id, state) do
    if export_enabled?(state.config) do
      list_exportable_scenes_for_room(room_id)
      |> Enum.each(fn scene ->
        :ok = publish_scene_payloads(scene, state.config)
      end)
    end

    state
  end

  defp publish_scene(scene_id, state) do
    if export_enabled?(state.config) do
      case exportable_scene(scene_id) do
        %Scene{} = scene -> :ok = publish_scene_payloads(scene, state.config)
        nil -> :ok
      end
    end

    state
  end

  defp unpublish_scene(scene_id, state) do
    if export_enabled?(state.config) do
      discovery = discovery_topic(scene_id, state.config.discovery_prefix)
      attributes = attributes_topic(scene_id)

      :ok = publish(discovery, "", retain: true)
      :ok = publish(attributes, "", retain: true)
    end

    state
  end

  defp publish_scene_payloads(%Scene{} = scene, config) do
    discovery = discovery_topic(scene.id, config.discovery_prefix)
    attributes = attributes_topic(scene.id)

    :ok = publish(discovery, Jason.encode!(discovery_payload(scene, config)), retain: true)
    :ok = publish(attributes, Jason.encode!(scene_attributes_payload(scene)), retain: true)
  end

  defp publish_availability_if_connected(state, value) do
    if connection_alive?(state.connection_pid) do
      :ok = publish_availability(value)
    end

    state
  end

  defp publish_availability(value) do
    publish(availability_topic(), value, retain: true)
  end

  defp publish(topic, payload, opts) do
    publish_opts = [qos: 0, retain: Keyword.get(opts, :retain, false)]

    case tortoise_module().publish(client_id(), topic, payload, publish_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish Home Assistant export MQTT payload: #{inspect(reason)}")
        :ok
    end
  end

  defp list_exportable_scenes do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        preload: [room: r],
        order_by: [asc: r.name, asc: s.name]
      )
    )
  end

  defp list_exportable_scenes_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        where: s.room_id == ^room_id,
        preload: [room: r],
        order_by: [asc: s.name]
      )
    )
  end

  defp exportable_scene(scene_id) when is_integer(scene_id) do
    Repo.one(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        where: s.id == ^scene_id,
        preload: [room: r]
      )
    )
  end

  defp maybe_put_auth(opts, %{username: username, password: password}) when is_binary(username) do
    opts
    |> Keyword.put(:user_name, username)
    |> maybe_put_password(password)
  end

  defp maybe_put_auth(opts, _config), do: opts

  defp maybe_put_password(opts, password) when is_binary(password),
    do: Keyword.put(opts, :password, password)

  defp maybe_put_password(opts, _password), do: opts

  defp room_name(%Room{} = room), do: room.display_name || room.name
  defp room_name(_room), do: "Unknown Room"

  defp scene_name(%Scene{} = scene), do: scene.display_name || scene.name

  defp export_enabled?(%{enabled: true, host: host}) when is_binary(host),
    do: String.trim(host) != ""

  defp export_enabled?(_config), do: false

  defp same_config?(nil, _config), do: false
  defp same_config?(left, right), do: left == right

  defp connection_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp connection_alive?(_pid), do: false

  defp normalize_payload(payload) when is_binary(payload), do: String.trim(payload)
  defp normalize_payload(payload), do: IO.iodata_to_binary(payload) |> String.trim()

  defp command_topic_filter do
    "#{@default_topic_prefix}/scenes/+/set"
  end

  defp tortoise_module do
    case Application.get_env(:hueworks, :ha_export_tortoise_module) do
      nil -> Tortoise
      module -> module
    end
  end

  defp supervisor_module do
    case Application.get_env(:hueworks, :ha_export_tortoise_supervisor_module) do
      nil -> Tortoise.Supervisor
      module -> module
    end
  end

  defp dynamic_supervisor_module do
    case Application.get_env(:hueworks, :ha_export_dynamic_supervisor_module) do
      nil -> DynamicSupervisor
      module -> module
    end
  end

  defp tortoise_supervisor_name do
    case Application.get_env(:hueworks, :ha_export_tortoise_supervisor_name) do
      nil -> Tortoise.Supervisor
      name -> name
    end
  end

  defmodule Handler do
    @moduledoc false

    use Tortoise.Handler

    def init([server, client_id, topic_filter]) do
      {:ok,
       %{
         server: server,
         client_id: client_id,
         subscriptions: [{topic_filter, 0}],
         subscribed?: false
       }}
    end

    def connection(:up, state) do
      case Tortoise.Connection.subscribe(state.client_id, state.subscriptions) do
        {:ok, _ref} ->
          send(state.server, {:mqtt_connected, state.client_id})
          {:ok, %{state | subscribed?: true}}

        {:error, _reason} ->
          {:ok, %{state | subscribed?: false}}
      end
    end

    def connection(:down, state), do: {:ok, %{state | subscribed?: false}}
    def connection(_status, state), do: {:ok, state}
    def subscription(_status, _topic_filter, state), do: {:ok, state}

    def handle_message(topic_levels, payload, state) do
      send(state.server, {:mqtt_message, topic_levels, payload})
      {:ok, state}
    end

    def terminate(_reason, _state), do: :ok
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, message)

      _ ->
        :ok
    end
  end
end
