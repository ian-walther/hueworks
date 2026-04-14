defmodule Hueworks.Subscription.Z2MEventStream.Connection do
  @moduledoc false

  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  @default_base_topic "zigbee2mqtt"
  @default_port 1883
  def start_link(%Bridge{} = bridge) do
    config = config_for_bridge(bridge)

    start_opts =
      [
        client_id: subscription_client_id(bridge.id),
        handler: {__MODULE__.Handler, [bridge.id, config.base_topic]},
        server: {Tortoise.Transport.Tcp, host: String.to_charlist(bridge.host), port: config.port}
      ]
      |> maybe_put_auth(config)

    case Tortoise.Supervisor.start_child(start_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def subscription_client_id(bridge_id),
    do: Hueworks.Instance.z2m_client_id("hwz2ms", bridge_id)

  defp config_for_bridge(bridge) do
    credentials = bridge.credentials || %{}

    %{
      base_topic: normalize_base_topic(Map.get(credentials, "base_topic")),
      port: normalize_port(Map.get(credentials, "broker_port")),
      username: normalize_optional(Map.get(credentials, "username")),
      password: normalize_optional(Map.get(credentials, "password"))
    }
  end

  defp normalize_base_topic(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: @default_base_topic, else: value
  end

  defp normalize_base_topic(_value), do: @default_base_topic

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

  defp maybe_put_auth(opts, %{username: username, password: password}) when is_binary(username) do
    opts
    |> Keyword.put(:user_name, username)
    |> maybe_put_password(password)
  end

  defp maybe_put_auth(opts, _config), do: opts

  defp maybe_put_password(opts, password) when is_binary(password),
    do: Keyword.put(opts, :password, password)

  defp maybe_put_password(opts, _password), do: opts

  defmodule Handler do
    @moduledoc false

    use Tortoise.Handler

    import Ecto.Query, only: [from: 2]

    alias Hueworks.Control.State
    alias Hueworks.Control.StateParser
    alias Hueworks.Repo
    alias Hueworks.Schemas.{Group, Light}

    @index_refresh_ms 2_000

    def init([bridge_id, base_topic]) do
      indexes = load_indexes(bridge_id)

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
             entity_from_topic(topic_levels, state),
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
          load_indexes(state.bridge_id)
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

    defp entity_from_topic(topic_levels, state) do
      base_levels = state.base_levels

      if Enum.take(topic_levels, length(base_levels)) == base_levels do
        rest = Enum.drop(topic_levels, length(base_levels))

        cond do
          rest == [] ->
            nil

          hd(rest) == "bridge" ->
            nil

          List.last(rest) in ["set", "get", "availability"] ->
            nil

          List.last(rest) == "state" and length(rest) > 1 ->
            rest
            |> Enum.drop(-1)
            |> Enum.join("/")

          true ->
            Enum.join(rest, "/")
        end
      else
        nil
      end
    end

    defp load_indexes(bridge_id) do
      lights =
        Repo.all(
          from(l in Light,
            where:
              l.bridge_id == ^bridge_id and l.source == :z2m and l.enabled == true and
                is_nil(l.canonical_light_id)
          )
        )

      groups =
        Repo.all(
          from(g in Group,
            where:
              g.bridge_id == ^bridge_id and g.source == :z2m and g.enabled == true and
                is_nil(g.canonical_group_id)
          )
        )

      lights_by_source_id =
        Enum.reduce(lights, %{}, fn light, acc -> Map.put(acc, light.source_id, light) end)

      groups_by_source_id =
        Enum.reduce(groups, %{}, fn group, acc -> Map.put(acc, group.source_id, group) end)

      group_member_lights =
        Enum.reduce(groups, %{}, fn group, acc ->
          members = get_in(group.metadata, ["members"]) || []

          lights =
            members
            |> Enum.map(&Map.get(lights_by_source_id, to_string(&1)))
            |> Enum.filter(&is_map/1)

          Map.put(acc, group.source_id, lights)
        end)

      %{
        lights_by_source_id: lights_by_source_id,
        groups_by_source_id: groups_by_source_id,
        group_member_lights: group_member_lights,
        group_source_ids_by_light_source_id: invert_group_members(group_member_lights)
      }
    end

    defp refresh_groups_for_light(light_source_id, state) do
      state.group_source_ids_by_light_source_id
      |> Map.get(light_source_id, [])
      |> Enum.each(&refresh_group_from_members(&1, state))
    end

    defp refresh_group_from_members(group_source_id, state) when is_binary(group_source_id) do
      with %Group{id: group_id} <- Map.get(state.groups_by_source_id, group_source_id),
           lights when is_list(lights) <- Map.get(state.group_member_lights, group_source_id),
           derived when derived != %{} <- derive_group_state(lights) do
        State.put(:group, group_id, derived)
      else
        _ -> :ok
      end
    end

    defp derive_group_state(lights) when is_list(lights) do
      states =
        lights
        |> Enum.map(&State.get(:light, &1.id))
        |> Enum.reject(&is_nil/1)

      on_states =
        Enum.filter(states, fn
          %{power: power} when power in [:on, "on", true] -> true
          _ -> false
        end)

      base =
        cond do
          on_states != [] -> %{power: :on}
          length(states) == length(lights) and states != [] -> %{power: :off}
          true -> %{}
        end

      base
      |> maybe_put_group_brightness(on_states)
      |> maybe_put_group_kelvin(on_states)
    end

    defp derive_group_state(_lights), do: %{}

    defp maybe_put_group_brightness(group_state, on_states) do
      brightness_values =
        on_states
        |> Enum.map(fn
          %{brightness: brightness} when is_number(brightness) -> brightness
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      if brightness_values != [] and length(brightness_values) == length(on_states) do
        Map.put(
          group_state,
          :brightness,
          round(Enum.sum(brightness_values) / length(brightness_values))
        )
      else
        group_state
      end
    end

    defp maybe_put_group_kelvin(group_state, on_states) do
      kelvin_values =
        on_states
        |> Enum.map(fn
          %{kelvin: kelvin} when is_number(kelvin) -> kelvin
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      if kelvin_values != [] and length(kelvin_values) == length(on_states) do
        min_k = Enum.min(kelvin_values)
        max_k = Enum.max(kelvin_values)

        if max_k - min_k <= 50 do
          Map.put(group_state, :kelvin, round(Enum.sum(kelvin_values) / length(kelvin_values)))
        else
          group_state
        end
      else
        group_state
      end
    end

    defp invert_group_members(group_member_lights) do
      Enum.reduce(group_member_lights, %{}, fn {group_source_id, lights}, acc ->
        Enum.reduce(lights, acc, fn light, inner ->
          Map.update(inner, light.source_id, [group_source_id], &[group_source_id | &1])
        end)
      end)
    end
  end
end
