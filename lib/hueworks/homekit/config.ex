defmodule Hueworks.HomeKit.Config do
  @moduledoc false

  alias Hueworks.AppSettings.HomeKitConfig
  alias Hueworks.Instance
  alias Hueworks.Schemas.AppSetting

  @model "HueWorks HomeKit Bridge"
  @accessory_type_bridge 2

  defstruct [
    :bridge_name,
    :data_path,
    :identifier,
    :pairing_code,
    :setup_id,
    :scenes_enabled
  ]

  def from_settings(%AppSetting{} = settings) do
    bridge_name = settings.homekit_bridge_name || HomeKitConfig.default_bridge_name()

    %__MODULE__{
      bridge_name: bridge_name,
      data_path: data_path(),
      identifier: stable_identifier(),
      pairing_code: stable_pairing_code(),
      setup_id: stable_setup_id(),
      scenes_enabled: settings.homekit_scenes_enabled == true
    }
  end

  def model, do: @model
  def accessory_type_bridge, do: @accessory_type_bridge

  defp data_path do
    Application.get_env(:hueworks, :homekit_data_path) ||
      Path.join(["data", "homekit", Instance.slug()])
  end

  defp stable_identifier do
    <<a, b, c, d, e, f, _rest::binary>> = digest("identifier")
    bytes = [Bitwise.bor(a, 0x02), b, c, d, e, f]

    bytes
    |> Enum.map_join(":", &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
    |> String.upcase()
  end

  defp stable_setup_id do
    "setup"
    |> digest()
    |> Base.encode32(case: :upper, padding: false)
    |> String.slice(0, 4)
  end

  defp stable_pairing_code do
    digits =
      "pairing-code"
      |> digest()
      |> :binary.bin_to_list()
      |> Enum.flat_map(fn byte -> Integer.digits(byte) end)
      |> Stream.cycle()
      |> Enum.take(8)
      |> Enum.join()

    <<a::binary-3, b::binary-2, c::binary-3>> = digits
    "#{a}-#{b}-#{c}"
  end

  defp digest(label) do
    :crypto.hash(:sha256, "hueworks:homekit:#{Instance.slug()}:#{label}")
  end
end
