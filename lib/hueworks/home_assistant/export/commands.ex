defmodule Hueworks.HomeAssistant.Export.Commands do
  @moduledoc false

  alias Hueworks.Control.State
  alias Hueworks.HomeAssistant.Export.Messages

  def normalize_light_command(%{} = payload, entity) when is_map(entity) do
    state = Messages.normalize_power_payload(Map.get(payload, "state"))
    brightness = Messages.normalize_export_brightness(Map.get(payload, "brightness"))

    kelvin =
      if entity.supports_temp == true do
        Messages.normalize_export_kelvin(Map.get(payload, "color_temp"))
      end

    {x, y} =
      if entity.supports_color == true do
        Messages.normalize_export_xy(Map.get(payload, "color"))
      else
        {nil, nil}
      end

    base_attrs =
      %{}
      |> maybe_put(:brightness, brightness)
      |> maybe_put(:kelvin, kelvin)
      |> maybe_put(:x, x)
      |> maybe_put(:y, y)

    attrs =
      base_attrs
      |> maybe_put(:power, if(map_size(base_attrs) > 0, do: :on))

    cond do
      state == :off ->
        {:ok, {:power, :off}}

      state == :on and map_size(attrs) == 0 ->
        {:ok, {:power, :on}}

      map_size(attrs) > 0 ->
        {:ok, {:set_state, attrs}}

      true ->
        :error
    end
  end

  def normalize_light_command(_payload, _entity), do: :error

  def decode_json_payload(payload) when is_binary(payload) do
    case Jason.decode(String.trim(payload)) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> :error
    end
  end

  def decode_json_payload(payload) do
    payload
    |> IO.iodata_to_binary()
    |> decode_json_payload()
  end

  def optimistic_power_state(kind, entity, power)
      when kind in [:light, :group] and is_map(entity) and power in [:on, :off] do
    case power do
      :off -> %{power: :off}
      :on -> merge_export_state(State.get(kind, entity.id) || %{}, %{power: :on})
    end
  end

  def optimistic_light_state(kind, entity, attrs)
      when kind in [:light, :group] and is_map(entity) and is_map(attrs) do
    merge_export_state(State.get(kind, entity.id) || %{}, attrs)
  end

  def merge_export_state(current, incoming) when is_map(current) and is_map(incoming) do
    current
    |> harmonize_color_and_temperature(incoming)
    |> Map.merge(incoming)
  end

  defp harmonize_color_and_temperature(attrs, incoming_attrs)
       when is_map(attrs) and is_map(incoming_attrs) do
    cond do
      incoming_has_xy?(incoming_attrs) ->
        drop_kelvin(attrs)

      incoming_has_kelvin?(incoming_attrs) ->
        drop_xy(attrs)

      true ->
        attrs
    end
  end

  defp harmonize_color_and_temperature(attrs, _incoming_attrs), do: attrs

  defp drop_kelvin(attrs) do
    attrs
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
  end

  defp drop_xy(attrs) do
    attrs
    |> Map.delete(:x)
    |> Map.delete("x")
    |> Map.delete(:y)
    |> Map.delete("y")
  end

  defp incoming_has_xy?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, :x) or Map.has_key?(attrs, "x") or Map.has_key?(attrs, :y) or
      Map.has_key?(attrs, "y")
  end

  defp incoming_has_xy?(_attrs), do: false

  defp incoming_has_kelvin?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, :kelvin) or Map.has_key?(attrs, "kelvin") or
      Map.has_key?(attrs, :temperature) or Map.has_key?(attrs, "temperature")
  end

  defp incoming_has_kelvin?(_attrs), do: false

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
