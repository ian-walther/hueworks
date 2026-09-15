defmodule Hueworks.HomeKit.LightBulbService do
  @moduledoc false
  # `public.hap.service.lightbulb` with HueWorks' wider color temperature range and, when
  # `iids` is given, explicit instance IDs from `Hueworks.HomeKit.AccessoryIds` so a
  # characteristic keeps its ID for life whatever else is added or removed. Built on the
  # library's `HAP.ServiceSource` extension point; the identity support itself lives in
  # the vendored fork (see vendor/hap/FORK.md).
  #
  # Without `iids` the library numbers characteristics by position, which is what the
  # default order below reproduces for an install upgrading from before IDs were
  # persisted: On, Brightness, Name first.

  alias Hueworks.HomeKit.AccessoryIds

  defstruct on: nil,
            brightness: nil,
            hue: nil,
            name: nil,
            saturation: nil,
            color_temperature: nil,
            iids: nil

  @doc "HAP types of the characteristics a service struct will publish, in default order."
  def present_types(%__MODULE__{} = value) do
    value
    |> characteristics()
    |> Enum.reject(fn {_module, source} -> is_nil(source) end)
    |> Enum.map(fn {module, _source} -> module.type() end)
  end

  @doc false
  def characteristics(%__MODULE__{} = value) do
    [
      {HAP.Characteristics.On, value.on},
      {HAP.Characteristics.Brightness, value.brightness},
      {HAP.Characteristics.Name, value.name},
      {Hueworks.HomeKit.Characteristics.ColorTemperature, value.color_temperature},
      {HAP.Characteristics.Hue, value.hue},
      {HAP.Characteristics.Saturation, value.saturation}
    ]
  end

  defimpl HAP.ServiceSource do
    def compile(value) do
      HAP.Service.ensure_required!(__MODULE__, "on", value.on)

      characteristics =
        value
        |> Hueworks.HomeKit.LightBulbService.characteristics()
        |> Enum.reject(fn {_module, source} -> is_nil(source) end)
        |> Enum.map(&with_iid(&1, value.iids))

      %HAP.Service{type: "43", iid: service_iid(value.iids), characteristics: characteristics}
    end

    defp with_iid(characteristic, nil), do: characteristic

    defp with_iid({module, source}, iids) when is_map(iids),
      do: {module, source, Map.fetch!(iids, module.type())}

    defp service_iid(nil), do: nil
    defp service_iid(iids) when is_map(iids), do: Map.fetch!(iids, AccessoryIds.service_key())
  end
end
