defmodule Hueworks.HomeAssistant.Export.Commands do
  @moduledoc false

  alias Hueworks.Control.LightStateSemantics
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
    LightStateSemantics.merge_state(current, incoming)
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
