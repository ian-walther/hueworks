defmodule Hueworks.Subscription.Z2MEventStream.Connection do
  @moduledoc false

  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Schemas.Bridge

  def start_link(%Bridge{} = bridge) do
    config = Z2MConfig.for_bridge(bridge)

    start_opts =
      [
        client_id: subscription_client_id(bridge.id),
        handler: {__MODULE__.Handler, [bridge.id, config.base_topic]},
        server: {Tortoise.Transport.Tcp, host: String.to_charlist(bridge.host), port: config.port}
      ]
      |> Keyword.merge(Z2MConfig.tortoise_auth_opts(config))

    case Tortoise.Supervisor.start_child(start_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def subscription_client_id(bridge_id),
    do: Hueworks.Instance.z2m_client_id("hwz2ms", bridge_id)

  defmodule Handler do
    @moduledoc false

    use Tortoise.Handler

    alias Hueworks.Control.GroupState
    alias Hueworks.Control.State
    alias Hueworks.Control.StateParser
    alias Hueworks.Control.Z2MTopology
    alias Hueworks.Schemas.{Group, Light}

    @index_refresh_ms 2_000

    def init([bridge_id, base_topic]) do
      indexes = Z2MTopology.load_indexes(bridge_id)

      {:ok,
       Map.merge(indexes, %{
         bridge_id: bridge_id,
         client_id:
           Hueworks.Subscription.Z2MEventStream.Connection.subscription_client_id(bridge_id),
         base_topic: base_topic,
         base_levels: String.split(base_topic, "/", trim: true),
         last_refresh_at: System.monotonic_time(:millisecond),
         subscriptions: [{"#{base_topic}/#", 0}],
         subscribed?: false
       })}
    end

    def connection(:up, state) do
      client_id = state.client_id

      case Tortoise.Connection.subscribe(client_id, state.subscriptions) do
        {:ok, _ref} ->
          {:ok, %{state | subscribed?: true}}

        {:error, _reason} ->
          {:ok, %{state | subscribed?: false}}
      end
    end

    def connection(:down, state), do: {:ok, %{state | subscribed?: false}}
    def connection(_status, state), do: {:ok, state}

    def subscription(_status, _topic_filter, state), do: {:ok, state}

    def handle_message(topic_levels, payload, state) do
      with entity_source_id when is_binary(entity_source_id) <-
             Z2MTopology.entity_from_topic(topic_levels, state.base_levels),
           {:ok, decoded} <- Jason.decode(IO.iodata_to_binary(payload)),
           true <- is_map(decoded) do
        {:ok, handle_entity_state(entity_source_id, decoded, state)}
      else
        _ -> {:ok, state}
      end
    end

    def terminate(_reason, _state), do: :ok

    defp handle_entity_state(entity_source_id, payload, state) do
      case Map.get(state.lights_by_source_id, entity_source_id) do
        %Light{} = light ->
          maybe_put_light(light, payload, state)
          state

        nil ->
          case Map.get(state.groups_by_source_id, entity_source_id) do
            %Group{} = group ->
              maybe_put_group(group, payload, state)

              state

            nil ->
              maybe_refresh_and_retry(entity_source_id, payload, state)
          end
      end
    end

    defp maybe_refresh_and_retry(entity_source_id, payload, state) do
      now = System.monotonic_time(:millisecond)

      if now - state.last_refresh_at < @index_refresh_ms do
        state
      else
        refreshed =
          Z2MTopology.load_indexes(state.bridge_id)
          |> Map.put(:bridge_id, state.bridge_id)
          |> Map.put(:base_topic, state.base_topic)
          |> Map.put(:base_levels, state.base_levels)
          |> Map.put(:last_refresh_at, now)

        case Map.get(refreshed.lights_by_source_id, entity_source_id) do
          %Light{} = light ->
            maybe_put_light(light, payload, refreshed)
            refreshed

          nil ->
            case Map.get(refreshed.groups_by_source_id, entity_source_id) do
              %Group{} = group ->
                maybe_put_group(group, payload, refreshed)

                refreshed

              nil ->
                refreshed
            end
        end
      end
    end

    defp maybe_put_light(light, payload, state) do
      update = build_state(payload, light)

      if update != %{} do
        State.put(:light, light.id, update)
        refresh_groups_for_light(light.source_id, state)
      end
    end

    defp maybe_put_group(group, payload, state) do
      update = build_state(payload, group)

      if update != %{} do
        State.put(:group, group.id, update)
        refresh_group_from_members(group.source_id, state)
      end
    end

    defp build_state(payload, entity) do
      StateParser.z2m_state(payload, entity)
    end

    defp refresh_groups_for_light(light_source_id, state) do
      state.group_source_ids_by_light_source_id
      |> Map.get(light_source_id, [])
      |> Enum.each(&refresh_group_from_members(&1, state))
    end

    defp refresh_group_from_members(group_source_id, state) when is_binary(group_source_id) do
      with %Group{id: group_id} <- Map.get(state.groups_by_source_id, group_source_id),
           lights when is_list(lights) <- Map.get(state.group_member_lights, group_source_id),
           derived when derived != %{} <- derive_group_state_from_members(lights) do
        State.put(:group, group_id, derived)
      else
        _ -> :ok
      end
    end

    defp derive_group_state_from_members(lights) when is_list(lights) do
      states =
        lights
        |> Enum.map(&State.get(:light, &1.id))
        |> Enum.reject(&is_nil/1)

      GroupState.derive_from_states(states, length(lights))
    end
  end
end
