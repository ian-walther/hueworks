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
        server:
          {Tortoise.Transport.Tcp, host: String.to_charlist(bridge.host), port: config.port},
        subscriptions: [{"#{config.base_topic}/#", 0}]
      ]
      |> maybe_put_auth(config)

    case Tortoise.Supervisor.start_child(start_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def subscription_client_id(bridge_id), do: "hwz2ms#{bridge_id}"

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
         base_topic: base_topic,
         base_levels: String.split(base_topic, "/", trim: true),
         last_refresh_at: System.monotonic_time(:millisecond)
       })}
    end

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
          maybe_put_light(light, payload)
          state

        nil ->
          case Map.get(state.groups_by_source_id, entity_source_id) do
            %Group{} = group ->
              maybe_put_group(group, payload)

              state.group_member_light_ids
              |> Map.get(group.source_id, [])
              |> Enum.each(fn light_id ->
                State.put(:light, light_id, build_state(payload, nil))
              end)

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
            maybe_put_light(light, payload)
            refreshed

          nil ->
            case Map.get(refreshed.groups_by_source_id, entity_source_id) do
              %Group{} = group ->
                maybe_put_group(group, payload)

                refreshed.group_member_light_ids
                |> Map.get(group.source_id, [])
                |> Enum.each(fn light_id ->
                  State.put(:light, light_id, build_state(payload, nil))
                end)

                refreshed

              nil ->
                refreshed
            end
        end
      end
    end

    defp maybe_put_light(light, payload) do
      update = build_state(payload, light)
      if update != %{}, do: State.put(:light, light.id, update)
    end

    defp maybe_put_group(group, payload) do
      update = build_state(payload, group)
      if update != %{}, do: State.put(:group, group.id, update)
    end

    defp build_state(payload, entity) do
      %{}
      |> Map.merge(StateParser.power_map(payload["state"] || payload["power"]))
      |> Map.merge(StateParser.brightness_from_z2m_attrs(payload))
      |> Map.merge(StateParser.kelvin_from_z2m_attrs(payload, entity))
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

      group_member_light_ids =
        Enum.reduce(groups, %{}, fn group, acc ->
          members = get_in(group.metadata, ["members"]) || []

          light_ids =
            members
            |> Enum.map(&Map.get(lights_by_source_id, to_string(&1)))
            |> Enum.filter(&is_map/1)
            |> Enum.map(& &1.id)

          Map.put(acc, group.source_id, light_ids)
        end)

      %{
        lights_by_source_id: lights_by_source_id,
        groups_by_source_id: groups_by_source_id,
        group_member_light_ids: group_member_light_ids
      }
    end
  end
end
