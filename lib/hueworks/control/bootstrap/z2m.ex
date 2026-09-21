defmodule Hueworks.Control.Bootstrap.Z2M do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Bootstrap.Observations
  alias Hueworks.Control.GroupState
  alias Hueworks.Control.State
  alias Hueworks.Control.StateParser
  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Control.Z2MTopology
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light}

  @connection_timeout 3_000
  @subscription_timeout 3_000
  @collect_timeout 2_000

  def run do
    bridges = Repo.all(from(b in Bridge, where: b.type == :z2m and b.enabled == true))
    Enum.each(bridges, &run/1)
    :ok
  end

  def run(%Bridge{} = bridge) do
    with :ok <- Hueworks.RuntimeIO.ensure_enabled() do
      bootstrap_bridge(bridge)
    end
  end

  defp bootstrap_bridge(bridge) do
    indexes = Z2MTopology.load_indexes(bridge.id)

    observations = %{
      lights: Observations.capture(:light, indexes.lights_by_source_id),
      groups: Observations.capture(:group, indexes.groups_by_source_id)
    }

    entities =
      Map.values(indexes.lights_by_source_id) ++ Map.values(indexes.groups_by_source_id)

    if entities == [] do
      :ok
    else
      config = Z2MConfig.for_bridge(bridge)
      client_id = client_id(bridge.id)

      start_opts =
        [
          client_id: client_id,
          handler: {__MODULE__.Handler, [self()]},
          server:
            {Tortoise.Transport.Tcp, host: String.to_charlist(bridge.host), port: config.port},
          subscriptions: [{"#{config.base_topic}/#", 0}]
        ]
        |> Keyword.merge(Z2MConfig.tortoise_auth_opts(config))

      # This supervisor belongs to the bootstrap task, not the long-lived MQTT
      # runtime. Even an untrappable task exit tears down its temporary client.
      {:ok, supervisor} = Tortoise.Supervisor.start_link([])

      try do
        with {:ok, _pid} <- start_connection(start_opts, supervisor),
             :ok <- await_connection(client_id),
             :ok <- await_subscription(config.base_topic),
             :ok <- request_entity_states(client_id, config.base_topic, entities) do
          result =
            collect_updates(
              observations,
              String.split(config.base_topic, "/", trim: true),
              MapSet.new(Enum.map(entities, & &1.source_id))
            )

          recompute_group_states(indexes)
          result
        end
      after
        Supervisor.stop(supervisor)
      end
    end
  end

  defp start_connection(start_opts, supervisor) do
    case supervisor_module().start_child(start_opts, supervisor) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp await_connection(client_id) do
    case connection_module().connection(client_id, timeout: @connection_timeout) do
      {:ok, _socket} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp await_subscription(base_topic) do
    topic_filter = "#{base_topic}/#"

    receive do
      {:z2m_bootstrap_subscription, :up, ^topic_filter} ->
        :ok
    after
      @subscription_timeout ->
        {:error, :subscription_timeout}
    end
  end

  defp request_entity_states(client_id, base_topic, entities) do
    Enum.reduce_while(entities, :ok, fn entity, :ok ->
      topic = "#{base_topic}/#{entity.source_id}/get"

      case tortoise_module().publish(client_id, topic, Jason.encode!(get_payload(entity)), qos: 0) do
        :ok -> {:cont, :ok}
        {:ok, _ref} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp get_payload(entity) do
    %{"state" => "", "brightness" => ""}
    |> maybe_put_color_temp_request(entity)
  end

  defp maybe_put_color_temp_request(payload, %{supports_temp: true}) do
    payload
    |> Map.put("color_temp", "")
    |> Map.put("color_mode", "")
    |> Map.put("color", "")
  end

  defp maybe_put_color_temp_request(payload, _entity), do: payload

  defp collect_updates(indexes, base_levels, pending) do
    deadline = System.monotonic_time(:millisecond) + @collect_timeout
    do_collect(indexes, base_levels, pending, deadline)
  end

  defp do_collect(indexes, base_levels, pending, deadline) do
    if MapSet.size(pending) == 0 do
      :ok
    else
      remaining = max(0, deadline - System.monotonic_time(:millisecond))

      if remaining == 0 do
        {:error, :state_timeout}
      else
        receive do
          {:z2m_bootstrap_msg, topic_levels, payload} ->
            with entity_source_id when is_binary(entity_source_id) <-
                   Z2MTopology.entity_from_topic(topic_levels, base_levels),
                 {:ok, decoded} <- Jason.decode(IO.iodata_to_binary(payload)),
                 true <- is_map(decoded) do
              applied? = apply_entity_state(entity_source_id, decoded, indexes)

              do_collect(
                indexes,
                base_levels,
                if(applied?, do: MapSet.delete(pending, entity_source_id), else: pending),
                deadline
              )
            else
              _ -> do_collect(indexes, base_levels, pending, deadline)
            end
        after
          remaining ->
            {:error, :state_timeout}
        end
      end
    end
  end

  defp apply_entity_state(entity_source_id, payload, indexes) do
    case Map.get(indexes.lights, entity_source_id) do
      {%Light{} = light, _version} = entry ->
        update = StateParser.z2m_state(payload, light)
        Observations.put(:light, entry, update)
        update != %{}

      nil ->
        case Map.get(indexes.groups, entity_source_id) do
          {%Group{} = group, _version} = entry ->
            update = StateParser.z2m_state(payload, group)
            Observations.put(:group, entry, update)
            update != %{}

          nil ->
            false
        end
    end
  end

  defp recompute_group_states(indexes) do
    Enum.each(Map.keys(indexes.group_member_lights), fn group_source_id ->
      with %{id: group_id} <- Map.get(indexes.groups_by_source_id, group_source_id),
           lights when is_list(lights) <- Map.get(indexes.group_member_lights, group_source_id),
           derived when derived != %{} <-
             lights |> Enum.map(& &1.id) |> GroupState.derive_from_light_ids() do
        State.put(:group, group_id, derived)
      else
        _ -> :ok
      end
    end)
  end

  defp client_id(bridge_id), do: "hwz2mb#{bridge_id}_#{System.unique_integer([:positive])}"

  defp tortoise_module do
    Application.get_env(:hueworks, :z2m_bootstrap_tortoise_module, Tortoise)
  end

  defp supervisor_module do
    Application.get_env(:hueworks, :z2m_bootstrap_tortoise_supervisor_module, Tortoise.Supervisor)
  end

  defp connection_module do
    Application.get_env(:hueworks, :z2m_bootstrap_tortoise_connection_module, Tortoise.Connection)
  end

  defmodule Handler do
    @moduledoc false

    use Tortoise.Handler

    def init([owner]) when is_pid(owner), do: {:ok, owner}

    def connection(_status, owner), do: {:ok, owner}

    def subscription(status, topic_filter, owner) do
      send(owner, {:z2m_bootstrap_subscription, status, topic_filter})
      {:ok, owner}
    end

    def handle_message(topic_levels, payload, owner) do
      send(owner, {:z2m_bootstrap_msg, topic_levels, payload})
      {:ok, owner}
    end

    def terminate(_reason, _owner), do: :ok
  end
end
