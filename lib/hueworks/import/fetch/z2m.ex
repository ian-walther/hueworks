defmodule Hueworks.Import.Fetch.Z2M do
  @moduledoc """
  Fetch Zigbee2MQTT snapshot data over MQTT for import.
  """

  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Import.Fetch.Common

  @snapshot_timeout 8_000

  def fetch do
    :z2m
    |> Common.load_enabled_bridge!()
    |> fetch_for_bridge()
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
    Z2MConfig.for_bridge(bridge)
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
      |> Keyword.merge(Z2MConfig.tortoise_auth_opts(config))

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

  defp deadline, do: System.monotonic_time(:millisecond) + @snapshot_timeout

  defp normalize_device_payload(payload) when is_list(payload), do: payload
  defp normalize_device_payload(%{"devices" => devices}) when is_list(devices), do: devices
  defp normalize_device_payload(_payload), do: []

  defp normalize_group_payload(payload) when is_list(payload), do: payload
  defp normalize_group_payload(%{"groups" => groups}) when is_list(groups), do: groups
  defp normalize_group_payload(_payload), do: []

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
