defmodule Hueworks.Picos.ControlGroups do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Picos.Devices
  alias Hueworks.Picos.Targets
  alias Hueworks.Repo
  alias Hueworks.Schemas.{PicoButton, PicoDevice}

  def normalize(groups) when is_list(groups) do
    groups
    |> Enum.flat_map(fn
      %{} = group ->
        id = Map.get(group, "id") || Map.get(group, :id)
        name = Map.get(group, "name") || Map.get(group, :name)

        if is_binary(id) and is_binary(name) and String.trim(name) != "" do
          [
            %{
              "id" => id,
              "name" => String.trim(name),
              "group_ids" =>
                group
                |> Map.get("group_ids", Map.get(group, :group_ids))
                |> Targets.normalize_integer_ids(),
              "light_ids" =>
                group
                |> Map.get("light_ids", Map.get(group, :light_ids))
                |> Targets.normalize_integer_ids()
            }
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  def normalize(_groups), do: []

  def list_for_device(%PicoDevice{} = device) do
    device
    |> Map.get(:metadata, %{})
    |> Map.get("control_groups", [])
    |> normalize()
  end

  def save(%PicoDevice{} = device, attrs) when is_map(attrs) do
    with room_id when is_integer(room_id) <- device.room_id,
         name when is_binary(name) and name != "" <- String.trim(attrs["name"] || ""),
         group_id <- attrs["id"] || Ecto.UUID.generate() do
      group_ids = Targets.normalize_integer_ids(attrs["group_ids"])
      light_ids = Targets.normalize_integer_ids(attrs["light_ids"])

      if Targets.valid_room_targets?(room_id, group_ids, light_ids) do
        updated_groups =
          device
          |> list_for_device()
          |> Enum.reject(&(&1["id"] == group_id))
          |> Kernel.++([
            %{
              "id" => group_id,
              "name" => name,
              "group_ids" => group_ids,
              "light_ids" => light_ids
            }
          ])
          |> Enum.sort_by(&String.downcase(&1["name"]))

        update_device_metadata(device, fn metadata ->
          Map.put(metadata, "control_groups", updated_groups)
        end)
      else
        {:error, :invalid_targets}
      end
    else
      nil -> {:error, :missing_room}
      _ -> {:error, :invalid_name}
    end
  end

  def delete(%PicoDevice{} = device, group_id) when is_binary(group_id) do
    control_groups = Enum.reject(list_for_device(device), &(&1["id"] == group_id))

    Repo.transaction(fn ->
      update_device_metadata!(device, fn metadata ->
        Map.put(metadata, "control_groups", control_groups)
      end)

      Repo.update_all(
        from(pb in PicoButton,
          where: pb.pico_device_id == ^device.id,
          where: fragment("?->>'target_kind' = 'control_group'", pb.action_config),
          where: fragment("?->>'target_id' = ?", pb.action_config, ^group_id)
        ),
        set: [action_type: nil, action_config: %{}, enabled: true]
      )
    end)

    {:ok, Devices.get(device.id)}
  end

  def clone_for_copy(%PicoDevice{} = device) do
    device
    |> list_for_device()
    |> Enum.map(fn group ->
      %{
        "id" => Ecto.UUID.generate(),
        "source_id" => group["id"],
        "name" => group["name"],
        "group_ids" => group["group_ids"],
        "light_ids" => group["light_ids"]
      }
    end)
  end

  defp update_device_metadata(%PicoDevice{} = device, fun) when is_function(fun, 1) do
    device
    |> PicoDevice.changeset(%{metadata: fun.(device.metadata || %{})})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Devices.get(updated.id)}
      other -> other
    end
  end

  defp update_device_metadata!(%PicoDevice{} = device, fun) when is_function(fun, 1) do
    device
    |> PicoDevice.changeset(%{metadata: fun.(device.metadata || %{})})
    |> Repo.update!()
  end
end
