defmodule Hueworks.Z2M.Snapshot do
  @moduledoc false

  alias Hueworks.Control.Z2MConfig

  @snapshot_timeout 8_000

  def fetch(config) do
    topics = topics(config.base_topic)
    required_topics = [topics.devices, topics.groups]
    subscribe_topics = required_topics ++ [topics.info]

    case fetch_topics(config, required_topics, subscribe_topics) do
      {:ok, payloads} ->
        {:ok,
         %{
           bridge_info: Map.get(payloads, topics.info),
           devices: Map.fetch!(payloads, topics.devices),
           groups: Map.fetch!(payloads, topics.groups)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp topics(base_topic) do
    %{
      devices: "#{base_topic}/bridge/devices",
      groups: "#{base_topic}/bridge/groups",
      info: "#{base_topic}/bridge/info"
    }
  end

  defp fetch_topics(config, required_topics, subscribe_topics) do
    client_id = "hueworks_z2m_snapshot_#{System.unique_integer([:positive])}"

    start_opts =
      [
        client_id: client_id,
        handler: {Hueworks.Z2M.Snapshot.Handler, [self()]},
        server:
          {Tortoise.Transport.Tcp, host: String.to_charlist(config.host), port: config.port},
        subscriptions: Enum.map(subscribe_topics, &{&1, 0})
      ]
      |> Keyword.merge(Z2MConfig.tortoise_auth_opts(config))

    with {:ok, pid} <- Tortoise.Supervisor.start_child(start_opts) do
      try do
        await_topics(
          MapSet.new(required_topics),
          MapSet.new(subscribe_topics),
          %{},
          deadline()
        )
      after
        DynamicSupervisor.terminate_child(Tortoise.Supervisor, pid)
      end
    else
      {:error, reason} -> {:error, format_error(reason)}
      other -> {:error, format_error(other)}
    end
  end

  defp await_topics(%MapSet{map: map}, _subscribed_topics, payloads, _deadline)
       when map_size(map) == 0 do
    {:ok, payloads}
  end

  defp await_topics(pending, subscribed_topics, payloads, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, missing_topics_message(pending)}
    else
      receive do
        {:z2m_connection, _status} ->
          await_topics(pending, subscribed_topics, payloads, deadline)

        {:z2m_message, topic, raw_payload} ->
          handle_message(topic, raw_payload, pending, subscribed_topics, payloads, deadline)
      after
        remaining -> {:error, missing_topics_message(pending)}
      end
    end
  end

  defp handle_message(topic, raw_payload, pending, subscribed_topics, payloads, deadline) do
    if MapSet.member?(subscribed_topics, topic) do
      case Jason.decode(IO.iodata_to_binary(raw_payload)) do
        {:ok, decoded} ->
          await_topics(
            MapSet.delete(pending, topic),
            subscribed_topics,
            Map.put(payloads, topic, decoded),
            deadline
          )

        {:error, reason} ->
          if MapSet.member?(pending, topic) do
            {:error, "invalid JSON on #{topic}: #{inspect(reason)}"}
          else
            await_topics(pending, subscribed_topics, payloads, deadline)
          end
      end
    else
      await_topics(pending, subscribed_topics, payloads, deadline)
    end
  end

  defp missing_topics_message(pending) do
    missing =
      pending
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.join(", ")

    "timed out waiting for MQTT snapshot topics: #{missing}"
  end

  defp deadline, do: System.monotonic_time(:millisecond) + @snapshot_timeout

  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end

defmodule Hueworks.Z2M.Snapshot.Handler do
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
