defmodule Hueworks.AppSettings.SolarConfig do
  @moduledoc """
  Boundary module for solar/transition app settings.

  Owns parsing and normalization for: latitude, longitude, timezone,
  default_transition_ms, and scale_transition_by_brightness.

  Does not validate ranges — that is AppSetting.global_changeset's job.
  Does not change the persisted shape — these remain flat columns on AppSetting.
  """

  alias Hueworks.Util

  @doc """
  Normalizes a mixed-key attrs map to an atom-keyed map suitable for
  AppSetting.global_changeset. Missing fields are omitted, explicitly blank
  fields are preserved as nil, and invalid present fields return errors.
  """
  def normalize(attrs) when is_map(attrs) do
    parse_attrs(attrs)
  end

  def normalize(_), do: {:error, [{"solar_config", "must be a map"}]}

  @doc """
  Builds a fallback attrs map from Application config (no DB row present).
  """
  def fallback_attrs do
    config = Application.get_env(:hueworks, :global_solar_config, %{})

    %{
      latitude: Util.to_number(config[:latitude] || config["latitude"]),
      longitude: Util.to_number(config[:longitude] || config["longitude"]),
      timezone: fallback_value(parse_string(config[:timezone] || config["timezone"])),
      default_transition_ms: Application.get_env(:hueworks, :default_transition_ms, 0),
      scale_transition_by_brightness:
        Util.parse_optional_bool(
          Application.get_env(:hueworks, :scale_transition_by_brightness, false)
        ) == true
    }
  end

  defp parse_attrs(attrs) do
    {attrs, errors} =
      {%{}, []}
      |> parse_present_field(
        :latitude,
        get_field_value(attrs, :latitude, "latitude"),
        &parse_number/1
      )
      |> parse_present_field(
        :longitude,
        get_field_value(attrs, :longitude, "longitude"),
        &parse_number/1
      )
      |> parse_present_field(
        :timezone,
        get_field_value(attrs, :timezone, "timezone"),
        &parse_string/1
      )
      |> parse_present_field(
        :default_transition_ms,
        get_field_value(attrs, :default_transition_ms, "default_transition_ms"),
        &parse_non_negative_integer/1
      )
      |> parse_present_field(
        :scale_transition_by_brightness,
        get_field_value(attrs, :scale_transition_by_brightness, "scale_transition_by_brightness"),
        &parse_bool/1
      )

    case errors do
      [] -> {:ok, attrs}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp get_field_value(attrs, atom_key, string_key) do
    cond do
      Map.has_key?(attrs, atom_key) -> Map.get(attrs, atom_key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> :missing
    end
  end

  defp parse_present_field({attrs, errors}, _key, :missing, _parse_fn), do: {attrs, errors}

  defp parse_present_field({attrs, errors}, key, value, parse_fn) do
    case parse_fn.(value) do
      {:ok, parsed} ->
        {Map.put(attrs, key, parsed), errors}

      {:error, message} ->
        {attrs, [{Atom.to_string(key), message} | errors]}
    end
  end

  defp parse_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      {:ok, trimmed}
    end
  end

  defp parse_string(nil), do: {:ok, nil}
  defp parse_string(_), do: {:error, "must be a string"}

  defp parse_number(nil), do: {:ok, nil}

  defp parse_number(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case Util.to_number(value) do
        nil -> {:error, "must be a number"}
        number -> {:ok, number}
      end
    end
  end

  defp parse_number(value) when is_integer(value) or is_float(value), do: {:ok, value}
  defp parse_number(_), do: {:error, "must be a number"}

  defp parse_non_negative_integer(nil), do: {:ok, nil}
  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp parse_non_negative_integer(value) when is_integer(value), do: {:error, "must be >= 0"}

  defp parse_non_negative_integer(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case Integer.parse(value) do
        {n, ""} when n >= 0 -> {:ok, n}
        {_, ""} -> {:error, "must be >= 0"}
        _ -> {:error, "must be an integer"}
      end
    end
  end

  defp parse_non_negative_integer(_), do: {:error, "must be an integer"}

  defp parse_bool(nil), do: {:ok, nil}

  defp parse_bool(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case Util.parse_optional_bool(value) do
        nil -> {:error, "must be true or false"}
        parsed -> {:ok, parsed}
      end
    end
  end

  defp parse_bool(value) when is_boolean(value), do: {:ok, value}
  defp parse_bool(_), do: {:error, "must be true or false"}

  defp fallback_value({:ok, value}), do: value
end
