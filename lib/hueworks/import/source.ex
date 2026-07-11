defmodule Hueworks.Import.Source do
  @moduledoc false

  @sources [:hue, :ha, :caseta, :z2m]

  def normalize(source) when source in @sources, do: source
  def normalize("hue"), do: :hue
  def normalize("ha"), do: :ha
  def normalize("caseta"), do: :caseta
  def normalize("z2m"), do: :z2m
  def normalize(_source), do: nil

  def parse(nil), do: {:error, "Missing bridge type"}

  def parse(source) do
    case normalize(source) do
      nil -> {:error, "Unsupported bridge type: #{source}"}
      normalized -> {:ok, normalized}
    end
  end
end
