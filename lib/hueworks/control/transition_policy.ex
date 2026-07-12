defmodule Hueworks.Control.TransitionPolicy do
  @moduledoc false

  alias Hueworks.AppSettings

  @type scaling :: :brightness_delta | :none
  @type t :: %__MODULE__{duration_ms: non_neg_integer(), scaling: scaling()}

  defstruct duration_ms: 0, scaling: :none

  def manual do
    settings = AppSettings.get_global()

    new(
      settings.default_transition_ms || 0,
      if(settings.scale_transition_by_brightness == true, do: :brightness_delta, else: :none)
    )
  end

  def circadian, do: new(500, :none)

  def scene_activation(scene, override_ms \\ nil) do
    case override_ms || Map.get(scene, :activation_transition_ms) do
      duration_ms when is_integer(duration_ms) and duration_ms > 0 -> new(duration_ms, :none)
      _ -> manual()
    end
  end

  def new(duration_ms, scaling)
      when is_integer(duration_ms) and duration_ms >= 0 and
             scaling in [:brightness_delta, :none] do
    %__MODULE__{duration_ms: duration_ms, scaling: scaling}
  end
end
