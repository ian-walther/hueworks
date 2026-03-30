defmodule Hueworks.Control.Bootstrap.Z2M do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.State
  alias Hueworks.Control.StateParser
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light}
  alias Hueworks.Util

  @default_port 1883
  @default_base_topic "zigbee2mqtt"
  @connection_timeout 3_000
  @subscription_timeout 3_000
  @collect_timeout 2_000

  def run do
    bridges = Repo.all(from(b in Bridge, where: b.type == :z2m and b.enabled == true))
    Enum.each(bridges, &bootstrap_bridge/1)
    :ok
  end

  defp bootstrap_bridge(%Bridge{} = bridge) do
    indexes = load_indexes(bridge.id)

    entities =
      Map.values(indexes.lights_by_source_id) ++ Map.values(indexes.groups_by_source_id)

    if entities == [] do
      :ok
    else
      config = config_for_bridge(bridge)
      client_id = client_id(bridge.id)

      start_opts =
        [
          client_id: client_id,
          handler: {__MODULE__.Handler, [self()]},
          server:
            {Tortoise.Transport.Tcp, host: String.to_charlist(bridge.host), port: config.port},
          subscriptions: [{"#{config.base_topic}/#", 0}]
        ]
        |> maybe_put_auth(config)

      with {:ok, pid} <- start_connection(start_opts),
           :ok <- await_connection(client_id),
           :ok <- await_subscription(config.base_topic) do
        try do
          request_entity_states(client_id, config.base_topic, entities)

          collect_updates(
            indexes,
            String.split(config.base_topic, "/", trim: true),
            MapSet.new(Enum.map(entities, & &1.source_id))
          )
        after
          if is_pid(pid), do: Process.exit(pid, :shutdown)
        end
      else
        _ -> :ok
      end
    end
  end

  defp start_connection(start_opts) do
    case supervisor_module().start_child(start_opts) do
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
    Enum.each(entities, fn entity ->
      topic = "#{base_topic}/#{entity.source_id}/get"
      _ = tortoise_module().publish(client_id, topic, Jason.encode!(get_payload(entity)), qos: 0)
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

  defp do_collect(_indexes, _base_levels, %MapSet{map: map}, _deadline) when map_size(map) == 0 do
    :ok
  end

  defp do_collect(indexes, base_levels, pending, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      :ok
    else
      receive do
        {:z2m_bootstrap_msg, topic_levels, payload} ->
          with entity_source_id when is_binary(entity_source_id) <-
                 entity_from_topic(topic_levels, base_levels),
               {:ok, decoded} <- Jason.decode(IO.iodata_to_binary(payload)),
               true <- is_map(decoded) do
            apply_entity_state(entity_source_id, decoded, indexes)
            do_collect(indexes, base_levels, MapSet.delete(pending, entity_source_id), deadline)
          else
            _ -> do_collect(indexes, base_levels, pending, deadline)
          end
      after
        remaining ->
          :ok
      end
    end
  end

  defp apply_entity_state(entity_source_id, payload, indexes) do
    case Map.get(indexes.lights_by_source_id, entity_source_id) do
      %Light{} = light ->
        update = build_state(payload, light)
        if update != %{}, do: State.put(:light, light.id, update)

      nil ->
        case Map.get(indexes.groups_by_source_id, entity_source_id) do
          %Group{} = group ->
            update = build_state(payload, group)
            if update != %{}, do: State.put(:group, group.id, update)

            indexes.group_member_lights
            |> Map.get(group.source_id, [])
            |> Enum.each(fn light ->
              light_update = build_state(payload, light)
              if light_update != %{}, do: State.put(:light, light.id, light_update)
            end)

          nil ->
            :ok
        end
    end
  end

  defp build_state(payload, entity) do
    %{}
    |> Map.merge(StateParser.power_map(payload["state"] || payload["power"]))
    |> Map.merge(StateParser.brightness_from_z2m_attrs(payload))
    |> Map.merge(StateParser.kelvin_from_z2m_attrs(payload, entity))
  end

  defp entity_from_topic(topic_levels, base_levels) do
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
      group_member_lights: group_member_lights
    }
  end

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
    def init(owner) when is_pid(owner), do: {:ok, owner}
    def init(_), do: {:ok, self()}

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
