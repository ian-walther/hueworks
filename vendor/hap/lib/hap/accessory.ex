defmodule HAP.Accessory do
  @moduledoc """
  Represents a single accessory object, containing a number of services
  """

  defstruct name: "Generic HAP Accessory",
            model: "Generic HAP Model",
            manufacturer: "Generic HAP Manufacturer",
            serial_number: "Generic Serial Number",
            firmware_revision: "1.0",
            services: [],
            aid: nil

  @typedoc """
  Represents an accessory consisting of a number of services. Contains the following
  fields:

  * `name`: The name to assign to this accessory, for example 'Ceiling Fan'
  * `model`: The model name to assign to this accessory, for example 'FanCo Whisper III'
  * `manufacturer`: The manufacturer of this accessory, for example 'FanCo'
  * `serial_number`: The serial number of this accessory, for example '0012345'
  * `firmware_revision`: The firmware revision of this accessory, for example '1.0'
  * `services`: A list of services to include in this accessory
  * `aid`: An optional explicit accessory ID. When nil, the accessory's position in the
  accessory server's list is used, so IDs shift if that list changes. Give explicit IDs
  (and explicit service and characteristic `iid`s) to keep identities stable across
  configuration changes; controllers key rooms, scenes, and automations on them.
  """
  @type t :: %__MODULE__{
          name: name(),
          model: model(),
          manufacturer: manufacturer(),
          serial_number: serial_number(),
          firmware_revision: firmware_revision(),
          services: [HAP.Service.t()],
          aid: pos_integer() | nil
        }

  @typedoc """
  The name to advertise for this accessory, for example 'HAP Light Bulb'
  """
  @type name :: String.t()

  @typedoc """
  The model of this accessory, for example 'HAP Light Bulb Supreme'
  """
  @type model :: String.t()

  @typedoc """
  The manufacturer of this accessory, for example 'HAP Co.'
  """
  @type manufacturer :: String.t()

  @typedoc """
  The serial number of this accessory, for example '0012345'
  """
  @type serial_number :: String.t()

  @typedoc """
  The firmware recvision of this accessory, for example '1.0' or '1.0.1'
  """
  @type firmware_revision :: String.t()

  @doc false
  def compile(%__MODULE__{services: services} = accessory, default_aid \\ nil) do
    all_services =
      [%HAP.Services.AccessoryInformation{accessory: accessory}, %HAP.Services.ProtocolInformation{}] ++
        services

    compiled_services =
      all_services
      |> Enum.with_index()
      |> Enum.map(fn {service, service_index} -> HAP.Service.compile(service, service_index) end)

    aid = accessory.aid || default_aid
    validate_instance_ids!(aid, compiled_services)

    %{accessory | aid: aid, services: compiled_services}
  end

  @doc false
  def get_service(%__MODULE__{services: services}, iid) do
    case Enum.find(services, &(&1.iid == iid)) do
      nil -> {:error, -70_409}
      service -> {:ok, service}
    end
  end

  @doc false
  def find_characteristic(%__MODULE__{services: services}, iid) do
    Enum.find_value(services, {:error, -70_409}, fn service ->
      case HAP.Service.get_characteristic(service, iid) do
        {:ok, characteristic} -> {:ok, characteristic}
        {:error, _reason} -> nil
      end
    end)
  end

  # Services and characteristics share one instance ID namespace per accessory.
  defp validate_instance_ids!(aid, services) do
    iids =
      Enum.flat_map(services, fn service ->
        [service.iid | Enum.map(service.characteristics, &HAP.Characteristic.iid/1)]
      end)

    unless Enum.all?(iids, &(is_integer(&1) and &1 > 0)) do
      raise ArgumentError, "instance ids must be positive integers in accessory #{inspect(aid)}"
    end

    case iids -- Enum.uniq(iids) do
      [] ->
        :ok

      duplicates ->
        raise ArgumentError, "duplicate instance ids #{inspect(Enum.uniq(duplicates))} in accessory #{inspect(aid)}"
    end
  end
end
