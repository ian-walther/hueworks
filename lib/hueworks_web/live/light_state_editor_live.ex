defmodule HueworksWeb.LightStateEditorLive do
  use Phoenix.LiveView

  alias Hueworks.Color
  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Scenes
  alias Hueworks.Util

  @manual_keys ["mode", "brightness", "temperature", "hue", "saturation"]

  @circadian_numeric_fields [
    {"min_brightness", "Min Brightness (%)", 1, 100, 1},
    {"max_brightness", "Max Brightness (%)", 1, 100, 1},
    {"min_color_temp", "Min Color Temp (K)", 1000, 10000, 50},
    {"max_color_temp", "Max Color Temp (K)", 1000, 10000, 50},
    {"sunrise_offset", "Sunrise Offset (s)", -86400, 86400, 60},
    {"sunset_offset", "Sunset Offset (s)", -86400, 86400, 60},
    {"brightness_mode_time_dark", "Brightness Ramp Dark (s)", 0, 86_400, 60},
    {"brightness_mode_time_light", "Brightness Ramp Light (s)", 0, 86_400, 60}
  ]

  @circadian_time_fields [
    {"sunrise_time", "Sunrise Time"},
    {"min_sunrise_time", "Min Sunrise Time"},
    {"max_sunrise_time", "Max Sunrise Time"},
    {"sunset_time", "Sunset Time"},
    {"min_sunset_time", "Min Sunset Time"},
    {"max_sunset_time", "Max Sunset Time"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Light State",
       light_state_id: nil,
       light_state_type: :manual,
       light_state_name: "",
       light_state_config: manual_default_edits(),
       light_state_usages: [],
       save_error: nil,
       dirty: false
     )}
  end

  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :new_manual ->
          assign_new_state(socket, :manual)

        :new_circadian ->
          assign_new_state(socket, :circadian)

        :edit ->
          assign_existing_state(socket, params["id"])
      end

    {:noreply, socket}
  end

  def handle_event("update_form", params, socket) do
    {name, config} = merge_form_params(socket, params)

    {:noreply,
     assign(socket,
       light_state_name: name,
       light_state_config: config,
       save_error: nil,
       dirty: true
     )}
  end

  def handle_event("save", params, socket) do
    {name, config} = merge_form_params(socket, params)

    attrs = %{
      name: name,
      type: socket.assigns.light_state_type,
      config: config
    }

    case save_light_state(socket, attrs) do
      {:ok, updated_socket} ->
        {:noreply, updated_socket}

      {:error, message} ->
        {:noreply, assign(socket, save_error: message)}
    end
  end

  defp save_light_state(%{assigns: %{light_state_id: nil}} = socket, attrs) do
    case Scenes.create_light_state(attrs.name, attrs.type, attrs.config) do
      {:ok, _state} ->
        {:ok, push_navigate(socket, to: "/config")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Util.format_changeset_error(changeset)}

      {:error, _reason} ->
        {:error, "Unable to save light state."}
    end
  end

  defp save_light_state(socket, attrs) do
    case Scenes.update_light_state(socket.assigns.light_state_id, attrs) do
      {:ok, state} ->
        _ = Scenes.refresh_active_scenes_for_light_state(state.id)
        {:ok, push_navigate(socket, to: "/config")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Util.format_changeset_error(changeset)}

      {:error, _reason} ->
        {:error, "Unable to save light state."}
    end
  end

  defp assign_new_state(socket, type) do
    assign(socket,
      page_title: new_page_title(type),
      light_state_id: nil,
      light_state_type: type,
      light_state_name: "",
      light_state_config: default_edits(type),
      light_state_usages: [],
      save_error: nil,
      dirty: false
    )
  end

  defp assign_existing_state(socket, id) do
    case Scenes.get_editable_light_state(parse_id(id)) do
      nil ->
        push_navigate(socket, to: "/config")

      state ->
        assign(socket,
          page_title: "Edit Light State",
          light_state_id: state.id,
          light_state_type: state.type,
          light_state_name: state.name,
          light_state_config: default_edits(state.type, state.config || %{}),
          light_state_usages: Scenes.light_state_usages(state.id),
          save_error: nil,
          dirty: false
        )
    end
  end

  defp new_page_title(:manual), do: "New Manual Light State"
  defp new_page_title(:circadian), do: "New Circadian Light State"

  defp default_edits(type, config \\ %{})
  defp default_edits(:manual, config), do: manual_default_edits(config)
  defp default_edits(:circadian, config), do: circadian_default_edits(config)

  defp manual_default_edits(config \\ %{}) do
    %{
      "mode" => manual_mode_from_config(config),
      "brightness" => config_value(config, "brightness"),
      "temperature" => config_value(config, "temperature"),
      "hue" => config_value(config, "hue"),
      "saturation" => config_value(config, "saturation")
    }
  end

  defp circadian_default_edits(config) do
    defaults =
      CircadianConfig.defaults()
      |> Enum.map(fn {key, value} -> {key, stringify_config_value(value)} end)
      |> Map.new()

    Enum.reduce(config, defaults, fn {key, value}, acc ->
      normalized_key = normalize_config_key(key)

      if normalized_key in circadian_form_keys() do
        Map.put(acc, normalized_key, stringify_config_value(value))
      else
        acc
      end
    end)
  end

  defp circadian_form_keys, do: CircadianConfig.supported_keys()
  defp circadian_numeric_fields, do: @circadian_numeric_fields
  defp circadian_time_fields, do: @circadian_time_fields

  defp stringify_config_value(nil), do: ""
  defp stringify_config_value(value) when is_binary(value), do: value
  defp stringify_config_value(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify_config_value(value) when is_float(value), do: Float.to_string(value)
  defp stringify_config_value(value), do: to_string(value)

  defp normalize_config_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_config_key(key) when is_binary(key), do: key
  defp normalize_config_key(key), do: to_string(key)

  defp config_value(config, key) do
    case config_lookup(config, key) do
      nil -> ""
      value -> value
    end
  end

  defp config_lookup(config, key) do
    cond do
      is_map(config) and Map.has_key?(config, key) ->
        Map.get(config, key)

      true ->
        atom_key = key_to_atom(key)

        if atom_key && is_map(config) && Map.has_key?(config, atom_key) do
          Map.get(config, atom_key)
        else
          nil
        end
    end
  end

  defp key_to_atom("brightness"), do: :brightness
  defp key_to_atom("temperature"), do: :temperature
  defp key_to_atom("hue"), do: :hue
  defp key_to_atom("saturation"), do: :saturation
  defp key_to_atom("mode"), do: :mode
  defp key_to_atom("min_brightness"), do: :min_brightness
  defp key_to_atom("max_brightness"), do: :max_brightness
  defp key_to_atom("min_color_temp"), do: :min_color_temp
  defp key_to_atom("max_color_temp"), do: :max_color_temp
  defp key_to_atom("sunrise_time"), do: :sunrise_time
  defp key_to_atom("min_sunrise_time"), do: :min_sunrise_time
  defp key_to_atom("max_sunrise_time"), do: :max_sunrise_time
  defp key_to_atom("sunrise_offset"), do: :sunrise_offset
  defp key_to_atom("sunset_time"), do: :sunset_time
  defp key_to_atom("min_sunset_time"), do: :min_sunset_time
  defp key_to_atom("max_sunset_time"), do: :max_sunset_time
  defp key_to_atom("sunset_offset"), do: :sunset_offset
  defp key_to_atom("brightness_mode"), do: :brightness_mode
  defp key_to_atom("brightness_mode_time_dark"), do: :brightness_mode_time_dark
  defp key_to_atom("brightness_mode_time_light"), do: :brightness_mode_time_light
  defp key_to_atom(_key), do: nil

  defp manual_mode_from_config(config) do
    case config_lookup(config || %{}, "mode") do
      "color" -> "color"
      :color -> "color"
      _ -> "temperature"
    end
  end

  defp manual_mode(assigns) do
    case Map.get(assigns.light_state_config, "mode") do
      "color" -> "color"
      :color -> "color"
      _ -> "temperature"
    end
  end

  defp manual_color_preview_style(assigns) do
    {r, g, b} = manual_color_rgb(assigns) || {143, 177, 255}
    "background-color: rgb(#{r} #{g} #{b});"
  end

  defp manual_color_preview_label(assigns) do
    hue = Map.get(assigns.light_state_config, "hue") |> normalize_preview_number(0)
    saturation = Map.get(assigns.light_state_config, "saturation") |> normalize_preview_number(100)
    brightness = Map.get(assigns.light_state_config, "brightness") |> normalize_preview_number(100)

    "Preview: #{hue}°, #{saturation}% saturation, #{brightness}% brightness"
  end

  defp manual_saturation_scale_style(assigns) do
    hue = Map.get(assigns.light_state_config, "hue") |> normalize_preview_number(0)
    brightness = Map.get(assigns.light_state_config, "brightness") |> normalize_preview_number(100)

    {r1, g1, b1} = Color.hsb_to_rgb(hue, 0, brightness) || {255, 255, 255}
    {r2, g2, b2} = Color.hsb_to_rgb(hue, 100, brightness) || {255, 255, 255}

    "background: linear-gradient(90deg, rgb(#{r1} #{g1} #{b1}), rgb(#{r2} #{g2} #{b2}));"
  end

  defp manual_color_rgb(assigns) do
    Color.hsb_to_rgb(
      Map.get(assigns.light_state_config, "hue"),
      Map.get(assigns.light_state_config, "saturation"),
      Map.get(assigns.light_state_config, "brightness")
    )
  end

  defp normalize_preview_number(value, fallback) do
    case Util.to_number(value) do
      number when is_number(number) -> round(number)
      _ -> fallback
    end
  end

  defp time_input_value(nil), do: ""
  defp time_input_value(""), do: ""

  defp time_input_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      <<hour::binary-size(2), ?:, minute::binary-size(2), ?:, second::binary-size(2)>> ->
        "#{hour}:#{minute}:#{second}"

      <<hour::binary-size(2), ?:, minute::binary-size(2)>> ->
        "#{hour}:#{minute}:00"

      other ->
        other
    end
  end

  defp time_input_value(value), do: stringify_config_value(value)

  defp parse_id(value), do: Util.parse_id(value)

  defp merge_form_params(socket, params) do
    name = Map.get(params, "name", socket.assigns.light_state_name)

    config =
      case socket.assigns.light_state_type do
        :manual ->
          Enum.reduce(@manual_keys, socket.assigns.light_state_config, fn key, acc ->
            if Map.has_key?(params, key) do
              Map.put(acc, key, Map.get(params, key))
            else
              acc
            end
          end)
          |> Map.put_new("mode", "temperature")

        :circadian ->
          Enum.reduce(circadian_form_keys(), socket.assigns.light_state_config, fn key, acc ->
            if Map.has_key?(params, key) do
              Map.put(acc, key, Map.get(params, key))
            else
              acc
            end
          end)
      end

    {name, config}
  end
end
