defmodule Hueworks.Control.State do
  @moduledoc """
  Shared in-memory control state backed by ETS.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Phoenix.PubSub

  @table :hueworks_control_state
  @topic "control_state"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}, {:continue, :bootstrap}}
  end

  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  def ensure(type, id, defaults) when is_map(defaults) do
    GenServer.call(__MODULE__, {:ensure, type, id, defaults})
  end

  def put(type, id, attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:put, type, id, attrs})
  end

  def bootstrap do
    GenServer.cast(__MODULE__, :bootstrap)
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  @impl true
  def handle_call({:ensure, type, id, defaults}, _from, state) do
    key = {type, id}

    case :ets.lookup(@table, key) do
      [{_key, current}] ->
        {:reply, current, state}

      [] ->
        :ets.insert(@table, {key, defaults})
        {:reply, defaults, state}
    end
  end

  @impl true
  def handle_call({:put, type, id, attrs}, _from, state) do
    key = {type, id}

    updated = merge_and_store(key, attrs)
    {:reply, updated, state}
  end

  @impl true
  def handle_cast(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end


  defp do_bootstrap do
    bootstrap_hue()
    bootstrap_home_assistant()
  end

  defp bootstrap_hue do
    bridges = Hueworks.Repo.all(from(b in Hueworks.Bridges.Bridge, where: b.type == :hue and b.enabled == true))

    Enum.each(bridges, fn bridge ->
      api_key = bridge.credentials["api_key"]

      if is_binary(api_key) and api_key != "" do
        lights = fetch_hue_endpoint(bridge.host, api_key, "/lights")
        groups = fetch_hue_endpoint(bridge.host, api_key, "/groups")
        lights_by_id = Hueworks.Import.Persist.lights_by_source_id(bridge.id, :hue)
        groups_by_id = Hueworks.Import.Persist.groups_by_source_id(bridge.id, :hue)

        Enum.each(lights, fn {id, light} ->
          case Map.get(lights_by_id, to_string(id)) do
            nil ->
              :ok

            db_light ->
              state = build_hue_light_state(light)
              merge_and_store({:light, db_light.id}, state)
          end
        end)

        Enum.each(groups, fn {id, group} ->
          case Map.get(groups_by_id, to_string(id)) do
            nil ->
              :ok

            db_group ->
              state = build_hue_group_state(group)
              merge_and_store({:group, db_group.id}, state)
          end
        end)
      end
    end)
  end

  defp fetch_hue_endpoint(host, api_key, endpoint) do
    url = "http://#{host}/api/#{api_key}#{endpoint}"

    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) -> data
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp build_hue_light_state(light) when is_map(light) do
    state = light["state"] || %{}
    %{}
    |> maybe_put_power(state["on"])
    |> maybe_put_brightness(state["bri"])
    |> maybe_put_kelvin_from_mired(state["ct"])
  end

  defp build_hue_light_state(_light), do: %{}

  defp build_hue_group_state(group) when is_map(group) do
    action = group["action"] || %{}
    %{}
    |> maybe_put_power(action["on"])
    |> maybe_put_brightness(action["bri"])
    |> maybe_put_kelvin_from_mired(action["ct"])
  end

  defp build_hue_group_state(_group), do: %{}

  defp bootstrap_home_assistant do
    bridge =
      Hueworks.Repo.one(from(b in Hueworks.Bridges.Bridge, where: b.type == :ha and b.enabled == true))

    if bridge do
      token = bridge.credentials["token"]

      if is_binary(token) and token != "" do
        lights_by_id = Hueworks.Import.Persist.lights_by_source_id(bridge.id, :ha)
        groups_by_id = Hueworks.Import.Persist.groups_by_source_id(bridge.id, :ha)
        states = fetch_ha_states(bridge.host, token)

        Enum.each(states, fn state ->
          entity_id = state["entity_id"]
          attrs = state["attributes"] || %{}
          current = build_ha_state(state["state"], attrs)

          case Map.get(lights_by_id, entity_id) do
            nil -> :ok
            db_light -> merge_and_store({:light, db_light.id}, current)
          end

          case Map.get(groups_by_id, entity_id) do
            nil -> :ok
            db_group -> merge_and_store({:group, db_group.id}, current)
          end
        end)
      end
    end
  end

  defp fetch_ha_states(host, token) do
    url = "http://#{normalize_ha_host(host)}/api/states"
    headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

    case HTTPoison.get(url, headers, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end

      _ ->
        []
    end
  end

  defp build_ha_state(state, attrs) do
    %{}
    |> maybe_put_power(state)
    |> maybe_put_brightness(attrs["brightness"])
    |> maybe_put_kelvin(attrs)
  end

  defp maybe_put_power(acc, true), do: Map.put(acc, :power, :on)
  defp maybe_put_power(acc, false), do: Map.put(acc, :power, :off)
  defp maybe_put_power(acc, "on"), do: Map.put(acc, :power, :on)
  defp maybe_put_power(acc, "off"), do: Map.put(acc, :power, :off)
  defp maybe_put_power(acc, _), do: acc

  defp maybe_put_brightness(acc, brightness) when is_number(brightness) do
    percent = round(brightness / 255 * 100)
    Map.put(acc, :brightness, clamp(percent, 1, 100))
  end

  defp maybe_put_brightness(acc, _), do: acc

  defp maybe_put_kelvin_from_mired(acc, mired) when is_number(mired) and mired > 0 do
    kelvin = round(1_000_000 / mired)
    Map.put(acc, :kelvin, kelvin)
  end

  defp maybe_put_kelvin_from_mired(acc, _), do: acc

  defp maybe_put_kelvin(acc, attrs) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        Map.put(acc, :kelvin, round(attrs["color_temp_kelvin"]))

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 ->
        Map.put(acc, :kelvin, round(1_000_000 / attrs["color_temp"]))

      true ->
        acc
    end
  end

  defp maybe_put_kelvin(acc, _attrs), do: acc

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end

  defp normalize_ha_host(host) when is_binary(host) do
    if String.contains?(host, ":") do
      host
    else
      "#{host}:8123"
    end
  end

  defp normalize_ha_host(_host), do: "127.0.0.1:8123"

  defp merge_and_store(key, attrs) do
    current =
      case :ets.lookup(@table, key) do
        [{_key, existing}] -> existing
        [] -> %{}
      end

    updated = Map.merge(current, attrs)
    :ets.insert(@table, {key, updated})
    broadcast_update(key, updated)
    updated
  end

  defp broadcast_update({type, id}, state) do
    PubSub.broadcast(Hueworks.PubSub, @topic, {:control_state, type, id, state})
  end
end
