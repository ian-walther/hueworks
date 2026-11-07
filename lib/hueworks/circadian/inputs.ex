defmodule Hueworks.Circadian.Inputs do
  @moduledoc """
  Normalized inputs for circadian calculations.

  Loading once gives runtime, preview samples, and every event marker the same
  profile config, effective timing, location, and timezone.
  """

  alias Hueworks.Circadian.Config
  alias Hueworks.Circadian.Timing
  alias Hueworks.Util

  @enforce_keys [:config, :timing, :latitude, :longitude, :timezone]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          config: map(),
          timing: Timing.t(),
          latitude: float() | nil,
          longitude: float() | nil,
          timezone: String.t()
        }

  def load(config, solar_config) when is_map(config) and is_map(solar_config) do
    with {:ok, runtime_config} <- Config.runtime(config),
         {:ok, global_window} <- Timing.global_window(solar_config) do
      {:ok,
       %__MODULE__{
         config: runtime_config,
         timing: Timing.resolve(runtime_config, global_window),
         latitude: coordinate(solar_config, :latitude),
         longitude: coordinate(solar_config, :longitude),
         timezone: timezone(solar_config)
       }}
    end
  end

  def load(_config, _solar_config), do: {:error, :invalid_args}

  defp coordinate(solar_config, key) do
    Util.to_float(Map.get(solar_config, key) || Map.get(solar_config, Atom.to_string(key)))
  end

  defp timezone(solar_config) do
    timezone = Map.get(solar_config, :timezone) || Map.get(solar_config, "timezone")

    if is_binary(timezone) and String.trim(timezone) != "", do: timezone, else: "Etc/UTC"
  end
end
