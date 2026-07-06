defmodule Hueworks.Import.Source do
  @moduledoc false

  @sources [:hue, :ha, :caseta, :z2m]

  def normalize(source) when source in @sources, do: source
  def normalize("hue"), do: :hue
  def normalize("ha"), do: :ha
  def normalize("caseta"), do: :caseta
  def normalize("z2m"), do: :z2m
  def normalize(_source), do: nil
end
