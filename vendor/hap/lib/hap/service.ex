defmodule HAP.Service do
  @moduledoc """
  Represents a single service, containing a number of characteristics
  """

  defstruct type: nil, characteristics: [], iid: nil

  @typedoc """
  Represents a service of a given type, containing a number of characteristics. `iid` may
  be given explicitly; when it is nil one is derived from the service's position in its
  accessory at compile time.
  """
  @type t :: %__MODULE__{
          type: type(),
          characteristics: [HAP.Characteristic.t()],
          iid: HAP.Characteristic.iid() | nil
        }

  @typedoc """
  The type of a service as defined in Section 6.6.1 of Apple's [HomeKit Accessory Protocol Specification](https://developer.apple.com/homekit/).
  """
  @type type :: String.t()

  @doc false
  @spec compile(HAP.ServiceSource.t(), non_neg_integer()) :: t()
  def compile(source, service_index \\ 0) do
    service = source |> HAP.ServiceSource.compile()

    characteristics =
      service.characteristics
      |> Enum.reject(fn characteristic -> is_nil(HAP.Characteristic.value_source(characteristic)) end)
      |> Enum.with_index()
      |> Enum.map(fn {characteristic, characteristic_index} ->
        HAP.Characteristic.compile(characteristic, HAP.IID.to_iid(service_index, characteristic_index))
      end)

    %{service | iid: service.iid || HAP.IID.to_iid(service_index), characteristics: characteristics}
  end

  @doc false
  def ensure_required!(module, name, nil), do: raise("Value for #{name} required for service definition #{module}")
  def ensure_required!(_module, _name, _characteristic_value), do: :ok

  @doc false
  def get_characteristic(%__MODULE__{characteristics: characteristics}, iid) do
    case Enum.find(characteristics, &(HAP.Characteristic.iid(&1) == iid)) do
      nil -> {:error, -70_409}
      characteristic -> {:ok, characteristic}
    end
  end

  defimpl HAP.ServiceSource do
    def compile(value), do: value
  end
end
