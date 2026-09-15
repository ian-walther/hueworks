defmodule Hueworks.HomeKit.Status do
  @moduledoc false
  # HAP status codes (HomeKit Accessory Protocol specification, table 6-11).
  # HomeKit only accepts integer codes in the `status` field of characteristic
  # responses; any other error shape is treated as a malformed reply.

  def unable_to_communicate, do: -70_402
  def busy, do: -70_403
  def read_only, do: -70_404
  def write_only, do: -70_405
  def not_found, do: -70_409
  def invalid_value, do: -70_410
end
