defmodule Hueworks.HomeKit.AccessoryIds do
  @moduledoc false
  # Permanent HomeKit identities.
  #
  # Apple Home keys rooms, names, scenes, and automations on an accessory's ID and on the
  # instance IDs of its characteristics. The vendored hap fork accepts explicit IDs, and
  # this module is their source of truth: an ID, once handed out, is never reused or
  # reassigned. An entity that stops being exposed keeps its accessory ID for when it
  # returns, and a characteristic that stops being published keeps its instance ID, so
  # nothing else ever moves.
  #
  # HAP requires accessory ID 1 to be the bridge itself. A fresh install reserves it for
  # the bridge accessory before any entity is numbered. An install that is already paired
  # when IDs are first persisted keeps the positional numbering it has always published
  # (its first entity at 1) so nothing moves in Apple Home; the graph supplies a bridge
  # accessory at 1 only if that entity stops being exposed.
  #
  # First assignment otherwise reproduces the positional scheme: accessories in lights,
  # groups, scenes order (each by name), the control service at 1025, and its
  # characteristics at 1027, 1029, ... in the service's default order.

  alias Hueworks.Repo
  alias Hueworks.Schemas.HomeKitAccessoryId

  @service_key "service"
  @bridge_serial_number "bridge"
  @legacy_service_iid 1025
  @legacy_first_characteristic_iid 1027
  @iid_step 2

  def service_key, do: @service_key
  def bridge_serial_number, do: @bridge_serial_number

  @doc """
  Returns the accessory ID for every serial number, assigning the next free ID to any
  serial number seen for the first time, in the order given. With `reserve_bridge?: true`
  a fresh install (no IDs yet) reserves ID 1 for the bridge accessory first; the result
  then also carries the bridge's ID under `bridge_serial_number/0`.
  """
  def assign(serial_numbers, opts \\ []) when is_list(serial_numbers) do
    existing = Map.new(Repo.all(HomeKitAccessoryId), &{&1.serial_number, &1.aid})

    existing =
      if existing == %{} and Keyword.get(opts, :reserve_bridge?, false) do
        %HomeKitAccessoryId{}
        |> HomeKitAccessoryId.changeset(%{serial_number: @bridge_serial_number, aid: 1})
        |> Repo.insert!()

        %{@bridge_serial_number => 1}
      else
        existing
      end

    next = (existing |> Map.values() |> Enum.max(fn -> 0 end)) + 1

    serial_numbers
    |> Enum.reduce({existing, next}, fn serial_number, {ids, next} ->
      if Map.has_key?(ids, serial_number) do
        {ids, next}
      else
        %HomeKitAccessoryId{}
        |> HomeKitAccessoryId.changeset(%{serial_number: serial_number, aid: next})
        |> Repo.insert!()

        {Map.put(ids, serial_number, next), next + 1}
      end
    end)
    |> elem(0)
    |> Map.take([@bridge_serial_number | serial_numbers])
  end

  @doc """
  Returns, for each serial number, the instance IDs of its control service and of every
  characteristic type it currently publishes (`"service"` plus HAP types). Types seen for
  the first time get the next free instance ID for that accessory, in the order given;
  types no longer published keep theirs. Changed maps are persisted.
  """
  def instance_ids(present_types_by_serial) when is_map(present_types_by_serial) do
    serial_numbers = Map.keys(present_types_by_serial)

    records =
      HomeKitAccessoryId
      |> Repo.all()
      |> Enum.filter(&(&1.serial_number in serial_numbers))
      |> Map.new(&{&1.serial_number, &1})

    Map.new(present_types_by_serial, fn {serial_number, present_types} ->
      record = Map.fetch!(records, serial_number)
      persisted = record.iids || %{}
      allocated = allocate(persisted, present_types)

      if allocated != persisted do
        record
        |> HomeKitAccessoryId.changeset(%{iids: allocated})
        |> Repo.update!()
      end

      {serial_number, allocated}
    end)
  end

  defp allocate(persisted, present_types) do
    iids = Map.put_new(persisted, @service_key, @legacy_service_iid)

    next =
      iids
      |> Map.values()
      |> Enum.max()
      |> Kernel.+(@iid_step)
      |> max(@legacy_first_characteristic_iid)

    present_types
    |> Enum.reduce({iids, next}, fn type, {iids, next} ->
      if Map.has_key?(iids, type) do
        {iids, next}
      else
        {Map.put(iids, type, next), next + @iid_step}
      end
    end)
    |> elem(0)
  end
end
