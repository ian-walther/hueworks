defmodule Hueworks.Subscription.HomeAssistantEventStream.Connection do
  @moduledoc false

  use WebSockex

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Util
  alias Hueworks.Control.State
  alias Hueworks.Kelvin
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
        subscribe(state)

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

  defp subscribe(state) do
    {id, state} = next_id(state)
    payload = %{"id" => id, "type" => "subscribe_events", "event_type" => "state_changed"}
    {:reply, {:text, Jason.encode!(payload)}, %{state | subscribed: true}}
  end

  defp handle_event(%{"data" => data}, state) do
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

  defp handle_event(_event, _state), do: :ok

  defp build_ha_state(state, entity) do
    attrs = state["attributes"] || %{}

    %{}
    |> maybe_put_power(state["state"])
    |> maybe_put_brightness(attrs["brightness"])
    |> maybe_put_kelvin(attrs, entity)
  end

  defp maybe_put_power(acc, true), do: Map.put(acc, :power, :on)
  defp maybe_put_power(acc, false), do: Map.put(acc, :power, :off)
  defp maybe_put_power(acc, "on"), do: Map.put(acc, :power, :on)
  defp maybe_put_power(acc, "off"), do: Map.put(acc, :power, :off)
  defp maybe_put_power(acc, _), do: acc

  defp maybe_put_brightness(acc, brightness) when is_number(brightness) do
    percent = round(brightness / 255 * 100)
    Map.put(acc, :brightness, Util.clamp(percent, 1, 100))
  end

  defp maybe_put_brightness(acc, _), do: acc

  defp maybe_put_kelvin(acc, attrs, entity) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        kelvin = Kelvin.map_from_event(entity, round(attrs["color_temp_kelvin"]))
        Map.put(acc, :kelvin, kelvin)

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 ->
        kelvin = round(1_000_000 / attrs["color_temp"])
        Map.put(acc, :kelvin, Kelvin.map_from_event(entity, kelvin))

      true ->
        acc
    end
  end

  defp maybe_put_kelvin(acc, _attrs, _entity), do: acc


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

    group_map = Enum.reduce(groups, %{}, fn group, acc -> Map.put(acc, group.source_id, group) end)

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