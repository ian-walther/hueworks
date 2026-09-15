defmodule Hueworks.HomeKit.Characteristics.ColorTemperature do
  @moduledoc false
  # HAP color temperature in mireds. The library's built-in definition stops at 400 mireds
  # (2500 K), which cuts off warm bulbs; 140..500 (7142 K to 2000 K) is the range
  # HAP-NodeJS publishes. Writes are clamped to each light's own kelvin range when applied.

  @behaviour HAP.CharacteristicDefinition

  def type, do: "CE"
  def perms, do: ["pr", "pw", "ev"]
  def format, do: "uint32"
  def min_value, do: 140
  def max_value, do: 500
  def step_value, do: 1
end
