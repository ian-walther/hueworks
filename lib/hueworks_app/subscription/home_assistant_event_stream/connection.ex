defmodule Hueworks.Subscription.HomeAssistantEventStream.Connection do
  @moduledoc false

  use WebSockex

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ExternalScenes
  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Control.State
  alias Hueworks.Control.StateParser
  alias Hueworks.Repo
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.Light

  def start_link(bridge) do
    url = "ws://#{Host.normalize(bridge.host)}/api/websocket"
    token = bridge.credentials["token"]

    if invalid_credential?(token) do
      Logger.warning("HA events missing token for #{bridge.name} (#{bridge.host})")
      {:error, :missing_token}
    else
      lights = load_lights(bridge.id)
      {groups, group_members} = load_groups(bridge.id, lights)

      state = %{
        bridge: bridge,
        token: token,
        next_id: 1,
        subscribed: false,
        state_changed_subscribed: false,
        call_service_subscribed: false,
        lights: lights,
        groups: groups,
        group_members: group_members
      }

      WebSockex.start_link(url, __MODULE__, state)
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, %{"type" => "auth_required"}} ->
        auth = %{"type" => "auth", "access_token" => state.token}
        {:reply, {:text, Jason.encode!(auth)}, state}

      {:ok, %{"type" => "auth_ok"}} ->
        subscribe_events(state, "state_changed")

      {:ok, %{"type" => "result", "success" => true}} ->
        maybe_subscribe_next_event_type(state)

      {:ok, %{"type" => "result"}} ->
        {:ok, state}

      {:ok, %{"type" => "event", "event" => event}} ->
        handle_event(event, state)
        {:ok, state}

      {:ok, _payload} ->
        {:ok, state}

      {:error, _reason} ->
        {:ok, state}
    end
  end

  defp subscribe_events(state, event_type) do
    {id, state} = next_id(state)
    payload = %{"id" => id, "type" => "subscribe_events", "event_type" => event_type}
    {:reply, {:text, Jason.encode!(payload)}, %{state | subscribed: true}}
  end

  defp maybe_subscribe_next_event_type(%{state_changed_subscribed: false} = state) do
    state = %{state | state_changed_subscribed: true}
    subscribe_events(state, "call_service")
  end

  defp maybe_subscribe_next_event_type(%{call_service_subscribed: false} = state) do
    {:ok, %{state | call_service_subscribed: true}}
  end

  defp maybe_subscribe_next_event_type(state), do: {:ok, state}

  defp handle_event(%{"event_type" => "state_changed", "data" => data}, state) do
    entity_id = data["entity_id"]
    new_state = data["new_state"]

    if is_binary(entity_id) and is_map(new_state) do
      case Map.get(state.lights, entity_id) do
        nil ->
          case Map.get(state.groups, entity_id) do
            nil ->
              :ok

            group ->
              state_update = build_ha_state(new_state, group)
              State.put(:group, group.id, state_update)

              # TODO: HA group fan-out has known edge cases with template entities; revisit after HA templates are removed.
              state.group_members
              |> Map.get(entity_id, [])
              |> Enum.each(fn light_id ->
                State.put(:light, light_id, state_update)
              end)
          end

        light ->
          State.put(:light, light.id, build_ha_state(new_state, light))
      end
    end
  end

  defp handle_event(%{"event_type" => "call_service", "data" => data}, state) do
    if data["domain"] == "scene" and data["service"] == "turn_on" do
      data
      |> scene_entity_ids_from_service_data()
      |> then(&ExternalScenes.activate_home_assistant_scenes(state.bridge.id, &1))
    else
      :ok
    end
  end

  defp handle_event(_event, _state), do: :ok

  defp scene_entity_ids_from_service_data(%{"service_data" => service_data}) when is_map(service_data) do
    direct_ids = normalize_entity_ids(service_data["entity_id"])
    target_ids = service_data |> Map.get("target", %{}) |> Map.get("entity_id") |> normalize_entity_ids()
    Enum.uniq(direct_ids ++ target_ids)
  end

  defp scene_entity_ids_from_service_data(_data), do: []

  defp normalize_entity_ids(nil), do: []
  defp normalize_entity_ids(value) when is_binary(value), do: [value]
  defp normalize_entity_ids(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_entity_ids(_value), do: []

  defp build_ha_state(state, entity) do
    attrs = state["attributes"] || %{}

    %{}
    |> Map.merge(StateParser.power_map(state["state"]))
    |> Map.merge(StateParser.brightness_from_0_255(attrs["brightness"]))
    |> Map.merge(StateParser.kelvin_from_ha_attrs(attrs, entity))
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
