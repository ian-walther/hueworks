defmodule Hueworks.HomeKit.ValueStore do
  @moduledoc false
  # HAP value store for HueWorks lights, groups, and scenes.
  #
  # Reads come from in-memory control state, overlaid with the last value HomeKit wrote
  # until the bridge confirms it. Writes are validated here and handed to
  # `Hueworks.HomeKit.Writer`, so the HAP request returns before any planning or bridge
  # traffic happens. Errors are HAP integer status codes; HomeKit rejects anything else.
  #
  # Color follows Home Assistant's HomeKit integration: HomeKit speaks hue/saturation and
  # mireds, HueWorks stores CIE xy and kelvin, and when a light is in temperature mode the
  # hue/saturation reported are those of its color temperature so the Home app's color
  # wheel matches.

  @behaviour HAP.ValueStore

  alias Hueworks.ActiveScenes
  alias Hueworks.Color
  alias Hueworks.Control.State
  alias Hueworks.DebugLogging
  alias Hueworks.Groups
  alias Hueworks.HomeKit
  alias Hueworks.Kelvin
  alias Hueworks.HomeKit.{Entities, Status, ValueCache, Writer}
  alias Hueworks.Schemas.Scene

  @entity_characteristics [:on, :brightness, :hue, :saturation, :color_temperature]
  @level_characteristics [:brightness, :hue, :saturation, :color_temperature]
  @min_mireds 140
  @max_mireds 500
  @default_mireds 370

  def entity_characteristics, do: @entity_characteristics

  @impl true
  def get_value(opts) do
    case target(opts) do
      {kind, id, characteristic}
      when kind in [:light, :group] and characteristic in @entity_characteristics ->
        {:ok,
         cached_or(kind, id, characteristic, fn ->
           observed_value(characteristic, entity_state(kind, id))
         end)}

      {:scene, id, :on} ->
        {:ok, cached_or(:scene, id, :on, fn -> scene_active?(id) end)}

      _ ->
        {:error, Status.not_found()}
    end
  end

  @impl true
  def put_value(value, opts) do
    started_ms = System.monotonic_time(:millisecond)
    result = do_put_value(value, opts)

    DebugLogging.info(
      "[homekit] write_accepted target=#{inspect(opts)} value=#{inspect(value)} result=#{inspect(result)} accept_ms=#{System.monotonic_time(:millisecond) - started_ms}"
    )

    result
  end

  @impl true
  def set_change_token(change_token, opts) do
    HomeKit.put_change_token(opts, change_token)
    :ok
  end

  @doc "Maps a control-state map onto the HomeKit value of a characteristic."
  def observed_value(:on, state) when is_map(state), do: match?(%{power: :on}, state)

  def observed_value(:brightness, state) when is_map(state) do
    case state do
      %{brightness: brightness} when is_number(brightness) -> clamp_brightness(brightness)
      _ -> 100
    end
  end

  def observed_value(:hue, state) when is_map(state) do
    case color_hs(state) do
      {hue, _saturation} -> hue * 1.0
      nil -> 0.0
    end
  end

  def observed_value(:saturation, state) when is_map(state) do
    case color_hs(state) do
      {_hue, saturation} -> saturation * 1.0
      nil -> 0.0
    end
  end

  def observed_value(:color_temperature, state) when is_map(state) do
    case state do
      %{kelvin: kelvin} when is_number(kelvin) and kelvin > 0 -> kelvin_to_mireds(kelvin)
      _ -> @default_mireds
    end
  end

  def observed_value(_characteristic, _state), do: nil

  @doc """
  Whether the observed state agrees with a value HomeKit wrote. Color round-trips through
  xy and kelvin, so hue, saturation, and mireds compare with a small tolerance.
  """
  def observed_matches?(characteristic, state, value) do
    case {characteristic, observed_value(characteristic, state)} do
      {:hue, observed} when is_number(observed) and is_number(value) ->
        delta = abs(observed - value)
        min(delta, 360 - delta) <= 2

      {:saturation, observed} when is_number(observed) and is_number(value) ->
        abs(observed - value) <= 2

      {:color_temperature, observed} when is_number(observed) and is_number(value) ->
        abs(observed - value) <= 5

      {_characteristic, observed} ->
        observed == value
    end
  end

  def kelvin_to_mireds(kelvin) when is_number(kelvin) and kelvin > 0 do
    (1_000_000 / kelvin) |> round() |> max(@min_mireds) |> min(@max_mireds)
  end

  def mireds_to_kelvin(mireds, min_kelvin, max_kelvin) when is_number(mireds) and mireds > 0 do
    (1_000_000 / mireds) |> round() |> max(min_kelvin) |> min(max_kelvin)
  end

  @doc "The hue and saturation a state map represents, from xy or from kelvin, or nil."
  def color_hs(%{x: x, y: y}) when is_number(x) and is_number(y), do: Color.xy_to_hs(x, y)

  def color_hs(%{kelvin: kelvin}) when is_number(kelvin) and kelvin > 0 do
    case Color.kelvin_to_xy(kelvin) do
      {x, y} -> Color.xy_to_hs(x, y)
      _ -> nil
    end
  end

  def color_hs(_state), do: nil

  defp do_put_value(value, opts) do
    case target(opts) do
      {kind, id, characteristic}
      when kind in [:light, :group] and characteristic in @entity_characteristics ->
        put_entity_value(kind, id, characteristic, value)

      {:scene, id, :on} ->
        put_scene_value(id, value)

      _ ->
        {:error, Status.not_found()}
    end
  end

  defp target(opts) do
    {Keyword.get(opts, :kind), Keyword.get(opts, :id), Keyword.get(opts, :characteristic, :on)}
  end

  defp cached_or(kind, id, characteristic, observed_fun) do
    case ValueCache.get(kind, id, characteristic) do
      {:ok, value} -> value
      :miss -> observed_fun.()
    end
  end

  defp entity_state(kind, id), do: State.get(kind, id) || %{}

  defp scene_active?(scene_id) do
    with %Scene{} = scene <- Entities.fetch_scene(scene_id),
         %{scene_id: active_scene_id} <- ActiveScenes.get_for_area(scene.area_id) do
      active_scene_id == scene.id
    else
      _ -> false
    end
  end

  defp put_entity_value(kind, id, characteristic, value) do
    with {:ok, target} <- resolve_target(kind, id),
         {:ok, normalized} <- normalize(characteristic, value),
         :ok <- ensure_writable(target, characteristic) do
      generation = ValueCache.put(kind, id, characteristic, normalized)
      supersede_other_color_mode(kind, id, characteristic, generation)
      Writer.submit(target, characteristic, normalized, generation)
      :ok
    end
  end

  defp resolve_target(kind, id) when is_integer(id) do
    with %{area_id: area_id} = entity when is_integer(area_id) <- Entities.fetch_entity(kind, id),
         light_ids when light_ids != [] <- target_light_ids(kind, entity) do
      # The effective range (calibrated over reported, extended where configured) is the
      # same one the web UI, API, and Home Assistant export use.
      {min_kelvin, max_kelvin} = Kelvin.derive_range(entity)

      {:ok,
       %{
         kind: kind,
         id: id,
         area_id: area_id,
         light_ids: light_ids,
         min_kelvin: min_kelvin,
         max_kelvin: max_kelvin
       }}
    else
      _ -> {:error, Status.unable_to_communicate()}
    end
  end

  defp resolve_target(_kind, _id), do: {:error, Status.not_found()}

  # A write in one color mode supersedes every earlier write in the other, including
  # ones already applied whose cache entries would otherwise keep masking the new mode
  # until they expired. Ordering by generation leaves newer accepted writes untouched.
  defp supersede_other_color_mode(kind, id, :color_temperature, generation),
    do: ValueCache.invalidate_older(kind, id, [:hue, :saturation], generation)

  defp supersede_other_color_mode(kind, id, characteristic, generation)
       when characteristic in [:hue, :saturation],
       do: ValueCache.invalidate_older(kind, id, [:color_temperature], generation)

  defp supersede_other_color_mode(_kind, _id, _characteristic, _generation), do: :ok

  defp target_light_ids(:light, light), do: [light.id]
  defp target_light_ids(:group, group), do: Groups.member_light_ids(group.id)

  defp normalize(:on, value), do: {:ok, value in [true, 1]}
  defp normalize(:brightness, value) when is_number(value), do: {:ok, clamp_brightness(value)}

  defp normalize(:hue, value) when is_number(value),
    do: {:ok, value |> max(0) |> min(360) |> Kernel.*(1.0)}

  defp normalize(:saturation, value) when is_number(value),
    do: {:ok, value |> max(0) |> min(100) |> Kernel.*(1.0)}

  defp normalize(:color_temperature, value) when is_number(value),
    do: {:ok, value |> round() |> max(@min_mireds) |> min(@max_mireds)}

  defp normalize(_characteristic, _value), do: {:error, Status.invalid_value()}

  # Brightness and color belong to the active scene while one owns the area, matching the
  # web UI, which refuses manual adjustment in that state. HomeKit is told the
  # characteristic cannot be written; the Home app reverts the control. Exposure is never
  # changed dynamically (see docs/homekit-internals.md, "Why exposure is static").
  defp ensure_writable(%{area_id: area_id}, characteristic)
       when characteristic in @level_characteristics do
    if ActiveScenes.get_for_area(area_id) do
      {:error, Status.read_only()}
    else
      :ok
    end
  end

  defp ensure_writable(_target, _characteristic), do: :ok

  defp put_scene_value(scene_id, value) when is_integer(scene_id) do
    case Entities.fetch_scene(scene_id) do
      %Scene{area_id: area_id} ->
        active? = value in [true, 1]
        generation = ValueCache.put(:scene, scene_id, :on, active?)
        Writer.submit_scene(%{id: scene_id, area_id: area_id}, active?, generation)
        :ok

      _ ->
        {:error, Status.not_found()}
    end
  end

  defp put_scene_value(_scene_id, _value), do: {:error, Status.not_found()}

  defp clamp_brightness(value) when is_number(value) do
    value
    |> round()
    |> max(0)
    |> min(100)
  end
end
