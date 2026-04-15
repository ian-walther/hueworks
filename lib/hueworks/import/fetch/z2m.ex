defmodule Hueworks.Import.Fetch.Z2M do
  @moduledoc """
  Fetch Zigbee2MQTT snapshot data over MQTT for import.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  @default_port 1883
  @default_base_topic "zigbee2mqtt"
  @snapshot_timeout 8_000

  def fetch do
    bridge = load_bridge(:z2m)
    fetch_for_bridge(bridge)
  end

  def fetch_for_bridge(bridge) do
    config = config_for_bridge(bridge)

    required_topics = required_topics(config.base_topic)
    subscribe_topics = required_topics ++ optional_topics(config.base_topic)

    case fetch_topics(config, required_topics, subscribe_topics) do
      {:ok, payloads} ->
        devices_topic = devices_topic(config.base_topic)
        groups_topic = groups_topic(config.base_topic)
        info_topic = info_topic(config.base_topic)

        %{
          broker_host: config.host,
          broker_port: config.port,
          base_topic: config.base_topic,
          bridge_info: Map.get(payloads, info_topic),
          devices: payloads |> Map.get(devices_topic) |> normalize_device_payload(),
          groups: payloads |> Map.get(groups_topic) |> normalize_group_payload()
        }

      {:error, reason} ->
        raise "Z2M fetch failed: #{reason}"
    end
  end

  defp config_for_bridge(bridge) do
    credentials = Bridge.credentials_struct(bridge)

    %{
      host: bridge.host,
      port: normalize_port(credentials.broker_port),
      username: normalize_optional(credentials.username),
      password: normalize_optional(credentials.password),
      base_topic: normalize_base_topic(credentials.base_topic)
    }
  end

  defp required_topics(base_topic), do: [devices_topic(base_topic), groups_topic(base_topic)]

  defp optional_topics(base_topic), do: [info_topic(base_topic)]

  defp devices_topic(base_topic), do: "#{base_topic}/bridge/devices"
  defp groups_topic(base_topic), do: "#{base_topic}/bridge/groups"
  defp info_topic(base_topic), do: "#{base_topic}/bridge/info"

  defp fetch_topics(config, required_topics, subscribe_topics) do
    client_id = "hueworks_z2m_import_#{System.unique_integer([:positive])}"

    start_opts =
      [
        client_id: client_id,
        handler: {Hueworks.Import.Fetch.Z2M.Handler, [self()]},
        server:
          {Tortoise.Transport.Tcp, host: String.to_charlist(config.host), port: config.port},
        subscriptions: Enum.map(subscribe_topics, &{&1, 0})
      ]
      |> maybe_put_auth(config)

    with {:ok, pid} <- Tortoise.Supervisor.start_child(start_opts) do
      try do
        await_topics(
          required_topics,
          MapSet.new(required_topics),
          MapSet.new(subscribe_topics),
          %{},
          deadline()
        )
      after
        DynamicSupervisor.terminate_child(Tortoise.Supervisor, pid)
      end
    else
      {:error, reason} ->
        {:error, format_error(reason)}

      other ->
        {:error, format_error(other)}
    end
  end

  defp await_topics(_required_topics, %MapSet{map: map}, _subscribed_topics, payloads, _deadline)
       when map_size(map) == 0 do
    {:ok, payloads}
  end

  defp await_topics(required_topics, pending, subscribed_topics, payloads, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      missing =
        pending
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.join(", ")

      {:error, "timed out waiting for MQTT snapshot topics: #{missing}"}
    else
      receive do
        {:z2m_connection, :down} ->
          await_topics(required_topics, pending, subscribed_topics, payloads, deadline)

        {:z2m_connection, :up} ->
          await_topics(required_topics, pending, subscribed_topics, payloads, deadline)

        {:z2m_message, topic, raw_payload} ->
          if MapSet.member?(subscribed_topics, topic) do
            case Jason.decode(IO.iodata_to_binary(raw_payload)) do
              {:ok, decoded} ->
                new_pending = MapSet.delete(pending, topic)
                new_payloads = Map.put(payloads, topic, decoded)

                if MapSet.size(new_pending) == 0 do
                  {:ok, new_payloads}
                else
                  await_topics(
                    required_topics,
                    new_pending,
                    subscribed_topics,
                    new_payloads,
                    deadline
                  )
                end

              {:error, reason} ->
                if MapSet.member?(pending, topic) do
                  {:error, "invalid JSON on #{topic}: #{inspect(reason)}"}
                else
                  await_topics(required_topics, pending, subscribed_topics, payloads, deadline)
                end
            end
          else
            await_topics(required_topics, pending, subscribed_topics, payloads, deadline)
          end
      after
        remaining ->
          missing =
            pending
            |> MapSet.to_list()
            |> Enum.sort()
            |> Enum.join(", ")

          {:error, "timed out waiting for MQTT snapshot topics: #{missing}"}
      end
    end
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

  defp deadline, do: System.monotonic_time(:millisecond) + @snapshot_timeout

  defp normalize_device_payload(payload) when is_list(payload), do: payload
  defp normalize_device_payload(%{"devices" => devices}) when is_list(devices), do: devices
  defp normalize_device_payload(_payload), do: []

  defp normalize_group_payload(payload) when is_list(payload), do: payload
  defp normalize_group_payload(%{"groups" => groups}) when is_list(groups), do: groups
  defp normalize_group_payload(_payload), do: []

  defp normalize_port(nil), do: @default_port

  defp normalize_port(value) do
    case Util.parse_optional_integer(value) do
      port when is_integer(port) and port > 0 and port <= 65_535 -> port
      _ -> @default_port
    end
  end

  defp normalize_optional(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional(_value), do: nil

  defp normalize_base_topic(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: @default_base_topic, else: value
  end

  defp normalize_base_topic(_value), do: @default_base_topic

  defp load_bridge(type) do
    Repo.one!(from(b in Bridge, where: b.type == ^type and b.enabled == true))
  end

  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end

defmodule Hueworks.Import.Fetch.Z2M.Handler do
  @moduledoc false

  use Tortoise.Handler

  def init([owner]) when is_pid(owner), do: {:ok, owner}
  def init(owner) when is_pid(owner), do: {:ok, owner}
  def init(_), do: {:ok, self()}

  def connection(status, owner) do
    send(owner, {:z2m_connection, status})
    {:ok, owner}
  end

  def subscription(_status, _topic_filter, owner), do: {:ok, owner}

  def handle_message(topic_levels, payload, owner) do
    send(owner, {:z2m_message, Enum.join(topic_levels, "/"), payload})
    {:ok, owner}
  end

  def terminate(_reason, _owner), do: :ok
end
