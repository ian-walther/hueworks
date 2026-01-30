defmodule Hueworks.Util do
  @moduledoc false

  def clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
end
