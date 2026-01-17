defmodule Hueworks.Control.Bootstrap.Hue do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Persist
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Control.State

  def run do
    bridges = Repo.all(from(b in Bridge, where: b.type == :hue and b.enabled == true))

    Enum.each(bridges, fn bridge ->
      api_key = bridge.credentials["api_key"]

      if is_binary(api_key) and api_key != "" do
        lights = fetch_hue_endpoint(bridge.host, api_key, "/lights")
        groups = fetch_hue_endpoint(bridge.host, api_key, "/groups")
        lights_by_id = Persist.lights_by_source_id(bridge.id, :hue)
        groups_by_id = Persist.groups_by_source_id(bridge.id, :hue)

        Enum.each(lights, fn {id, light} ->
          case Map.get(lights_by_id, to_string(id)) do
            nil ->
              :ok

            db_light ->
              state = build_hue_light_state(light)
              State.put(:light, db_light.id, state)
          end
        end)

        Enum.each(groups, fn {id, group} ->
          case Map.get(groups_by_id, to_string(id)) do
            nil ->
              :ok

            db_group ->
              state = build_hue_group_state(group)
              State.put(:group, db_group.id, state)
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

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
end
