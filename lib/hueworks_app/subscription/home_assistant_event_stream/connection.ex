defmodule Hueworks.Subscription.HomeAssistantEventStream.Connection do
  @moduledoc false

  use WebSockex

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ExternalScenes
  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Control.{DesiredState, GroupState, State}
  alias Hueworks.Control.StateParser
  alias Hueworks.Repo
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.Light
  alias Hueworks.Schemas.Bridge

  @refresh_interval_ms 2_000

  def start_link(bridge, websockex \\ WebSockex) do
    url = "ws://#{Host.normalize(bridge.host)}/api/websocket"
    token = Bridge.credentials_struct(bridge).token

    if invalid_credential?(token) do
      Logger.warning("HA events missing token for #{bridge.name} (#{bridge.host})")
      {:error, :missing_token}
    else
      state = %{
        bridge: bridge,
        token: token,
        next_id: 1,
        pending_subscriptions: ["state_changed", "call_service"],
        lights: %{},
        groups: %{},
        group_members: %{},
        last_refresh_at: 0
      }

      websockex.start_link(url, __MODULE__, state, async: true)
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    lights = load_lights(state.bridge.id)
    {groups, group_members} = load_groups(state.bridge.id, lights)

    state = %{state | lights: lights, groups: groups, group_members: group_members}

    {:ok, state}
  end

  @impl true
  def handle_frame({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, %{"type" => "auth_required"}} ->
        auth = %{"type" => "auth", "access_token" => state.token}
        {:reply, {:text, Jason.encode!(auth)}, state}

      {:ok, %{"type" => "auth_ok"}} ->
        subscribe_next_event_type(state)

      {:ok, %{"type" => "result", "success" => true}} ->
        subscribe_next_event_type(state)

      {:ok, %{"type" => "result"}} ->
        {:ok, state}

      {:ok, %{"type" => "event", "event" => event}} ->
        {:ok, handle_event(event, state)}

      {:ok, _payload} ->
        {:ok, state}

      {:error, _reason} ->
        {:ok, state}
    end
  end

  defp subscribe_next_event_type(%{pending_subscriptions: [event_type | rest]} = state) do
    state = %{state | pending_subscriptions: rest}
    subscribe_events(state, event_type)
  end

  defp subscribe_next_event_type(state), do: {:ok, state}

  defp subscribe_events(state, event_type) do
    {id, state} = next_id(state)
    payload = %{"id" => id, "type" => "subscribe_events", "event_type" => event_type}
    {:reply, {:text, Jason.encode!(payload)}, state}
  end

  defp handle_event(%{"event_type" => "state_changed", "data" => data}, state) do
    entity_id = data["entity_id"]
    new_state = data["new_state"]

    if is_binary(entity_id) and is_map(new_state) do
      state = maybe_refresh_indexes(state, entity_id)

      case Map.get(state.lights, entity_id) do
        nil ->
          case Map.get(state.groups, entity_id) do
            nil ->
              state

            group ->
              state_update = build_ha_state(new_state, group)
              State.put(:group, group.id, state_update)
              update_group_members_from_group_state(state, entity_id, group.id, state_update)
              state
          end

        light ->
          State.put(:light, light.id, build_ha_state(new_state, light))
          state
      end
    else
      state
    end
  end

  defp handle_event(%{"event_type" => "call_service", "data" => data}, state) do
    if data["domain"] == "scene" and data["service"] == "turn_on" do
      data
      |> scene_entity_ids_from_service_data()
      |> then(&ExternalScenes.activate_home_assistant_scenes(state.bridge.id, &1))
    end

    state
  end

  defp handle_event(_event, state), do: state

  defp maybe_refresh_indexes(state, entity_id) do
    if Map.has_key?(state.lights, entity_id) or Map.has_key?(state.groups, entity_id) do
      state
    else
      refresh_indexes_if_due(state)
    end
  end

  defp refresh_indexes_if_due(state) do
    now = System.monotonic_time(:millisecond)
    last_refresh_at = Map.get(state, :last_refresh_at)

    if refresh_due?(now, last_refresh_at) do
      lights = load_lights(state.bridge.id)
      {groups, group_members} = load_groups(state.bridge.id, lights)

      %{
        state
        | lights: lights,
          groups: groups,
          group_members: group_members,
          last_refresh_at: now
      }
    else
      state
    end
  end

  defp refresh_due?(_now, last_refresh_at) when last_refresh_at in [nil, 0], do: true
  defp refresh_due?(now, last_refresh_at), do: now - last_refresh_at > @refresh_interval_ms

  defp update_group_members_from_group_state(state, entity_id, group_id, state_update) do
    light_ids = Map.get(state.group_members, entity_id, [])

    Enum.each(light_ids, fn light_id ->
      State.put(
        :light,
        light_id,
        GroupState.member_attrs_from_group(
          state_update,
          DesiredState.get(:light, light_id),
          State.get(:light, light_id)
        )
      )
    end)

    case GroupState.derive_from_light_ids(light_ids) do
      derived when derived != %{} -> State.put(:group, group_id, derived)
      _ -> :ok
    end
  end

  defp scene_entity_ids_from_service_data(%{"service_data" => service_data})
       when is_map(service_data) do
    direct_ids = normalize_entity_ids(service_data["entity_id"])

    target_ids =
      service_data |> Map.get("target", %{}) |> Map.get("entity_id") |> normalize_entity_ids()

    Enum.uniq(direct_ids ++ target_ids)
  end

  defp scene_entity_ids_from_service_data(_data), do: []

  defp normalize_entity_ids(nil), do: []
  defp normalize_entity_ids(value) when is_binary(value), do: [value]
  defp normalize_entity_ids(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_entity_ids(_value), do: []

  defp build_ha_state(state, entity) do
    StateParser.home_assistant_state(state, entity)
  end

  defp load_lights(bridge_id) do
    Repo.all(
      from(l in Light,
        where:
          l.bridge_id == ^bridge_id and l.source == :ha and l.enabled == true and
            is_nil(l.canonical_light_id)
      )
    )
    |> Enum.reduce(%{}, fn light, acc -> Map.put(acc, light.source_id, light) end)
  end

  defp load_groups(bridge_id, lights_by_source_id) do
    groups =
      Repo.all(
        from(g in Group,
          where:
            g.bridge_id == ^bridge_id and g.source == :ha and g.enabled == true and
              is_nil(g.canonical_group_id)
        )
      )

    group_map =
      Enum.reduce(groups, %{}, fn group, acc -> Map.put(acc, group.source_id, group) end)

    members_map =
      Enum.reduce(groups, %{}, fn group, acc ->
        members = get_in(group.metadata, ["members"]) || []

        light_ids =
          members
          |> Enum.map(&Map.get(lights_by_source_id, to_string(&1)))
          |> Enum.filter(&is_map/1)
          |> Enum.map(& &1.id)

        Map.put(acc, group.source_id, light_ids)
      end)

    {group_map, members_map}
  end

  defp next_id(state) do
    {state.next_id, %{state | next_id: state.next_id + 1}}
  end

  defp invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end
end
