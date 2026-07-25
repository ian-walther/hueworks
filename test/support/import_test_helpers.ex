defmodule Hueworks.ImportTestHelpers do
  @moduledoc false

  def blob_shaped(value) do
    value
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
