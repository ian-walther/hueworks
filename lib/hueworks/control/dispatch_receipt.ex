defmodule Hueworks.Control.DispatchReceipt do
  @moduledoc false

  @type t :: %__MODULE__{effective_transition_ms: non_neg_integer()}

  defstruct effective_transition_ms: 0

  def new(duration_ms) when is_integer(duration_ms) and duration_ms >= 0 do
    %__MODULE__{effective_transition_ms: duration_ms}
  end

  def new(_duration_ms), do: %__MODULE__{}
end
