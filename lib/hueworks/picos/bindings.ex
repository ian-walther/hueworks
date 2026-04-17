defmodule Hueworks.Picos.Bindings do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Picos
  alias Hueworks.Picos.Targets
  alias Hueworks.Repo
  alias Hueworks.Schemas.PicoButton.ActionConfig, as: StoredActionConfig
  alias Hueworks.Schemas.{PicoButton, PicoDevice}
  alias Hueworks.Util

  @five_button_preset "overhead_lamps_all_toggle"

  def assign_button_binding(%PicoDevice{} = device, button_source_id, attrs)
      when is_binary(button_source_id) and is_map(attrs) do
    with room_id when is_integer(room_id) <- device.room_id,
         {:ok, action_type} <- binding_action_type(attrs["action"]),
         {:ok, action_config} <- binding_action_config(device, attrs) do
      case Repo.one(
             from(pb in PicoButton,
               where: pb.pico_device_id == ^device.id and pb.source_id == ^button_source_id
             )
           ) do
        nil ->
          {:error, :button_not_found}

        button ->
          button
          |> PicoButton.changeset(%{
            action_type: action_type,
            action_config: Map.put(action_config, "room_id", room_id),
            enabled: true
          })
          |> Repo.update()
      end
    else
      nil -> {:error, :missing_room}
      {:error, _} = error -> error
    end
  end

  def clear_button_binding(%PicoButton{} = button) do
    button
    |> Ecto.Changeset.change(%{
      action_type: nil,
      enabled: true
    })
    |> Ecto.Changeset.put_embed(:action_config, nil)
    |> Repo.update()
  end

  def save_five_button_preset(%PicoDevice{} = device, attrs) when is_map(attrs) do
    device = Repo.preload(device, buttons: from(pb in PicoButton, order_by: [asc: pb.slot_index]))

    with :ok <- validate_five_button_device(device),
         room_id when is_integer(room_id) <- device.room_id do
      primary =
        Targets.expand_room_targets(
          room_id,
          attrs["primary_group_ids"],
          attrs["primary_light_ids"]
        )

      secondary =
        Targets.expand_room_targets(
          room_id,
          attrs["secondary_group_ids"],
          attrs["secondary_light_ids"]
        )

      all_target = Enum.uniq(primary ++ secondary)
      buttons_by_slot = buttons_by_slot(device)

      button_updates = [
        {0, "turn_on", primary},
        {1, "turn_on", secondary},
        {2, "toggle_any_on", all_target},
        {3, "turn_off", secondary},
        {4, "turn_off", primary}
      ]

      Repo.transaction(fn ->
        Enum.each(button_updates, fn {slot_index, action_type, light_ids} ->
          button = Map.get(buttons_by_slot, slot_index)

          if button do
            button
            |> PicoButton.changeset(%{
              slot_index: slot_index,
              action_type: action_type,
              action_config: %{"light_ids" => light_ids},
              enabled: true,
              metadata: Map.put(button.metadata || %{}, "preset", @five_button_preset)
            })
            |> Repo.update!()
          end
        end)

        device
        |> PicoDevice.changeset(%{
          metadata:
            (device.metadata || %{})
            |> Map.put("preset", @five_button_preset)
            |> Map.put(
              "primary",
              normalize_saved_target(attrs["primary_group_ids"], attrs["primary_light_ids"])
            )
            |> Map.put(
              "secondary",
              normalize_saved_target(attrs["secondary_group_ids"], attrs["secondary_light_ids"])
            )
        })
        |> Repo.update!()
      end)

      {:ok, Picos.get_device(device.id)}
    else
      nil -> {:error, :missing_room}
      {:error, _} = error -> error
    end
  end

  def save_five_button_preset(_device, _attrs), do: {:error, :invalid_device}

  def clone_action_config(
        %StoredActionConfig{target_kind: :control_group} = config,
        group_id_map,
        room_id
      ) do
    target_id = StoredActionConfig.target_id(config)

    %{
      "target_kind" => "control_group",
      "target_id" => Map.get(group_id_map, target_id),
      "room_id" => room_id
    }
  end

  def clone_action_config(%StoredActionConfig{target_kind: :all_groups}, _group_id_map, room_id) do
    %{
      "target_kind" => "all_groups",
      "room_id" => room_id
    }
  end

  def clone_action_config(
        %StoredActionConfig{target_kind: :scene} = config,
        _group_id_map,
        room_id
      ) do
    target_id = StoredActionConfig.target_id(config)

    %{
      "target_kind" => "scene",
      "target_id" => target_id,
      "room_id" => room_id
    }
  end

  def clone_action_config(%StoredActionConfig{light_ids: light_ids}, _group_id_map, room_id)
      when light_ids != [] do
    %{
      "light_ids" => Targets.normalize_integer_ids(light_ids),
      "room_id" => room_id
    }
  end

  def clone_action_config(_config, _group_id_map, _room_id), do: %{}

  defp binding_action_type("on"), do: {:ok, "turn_on"}
  defp binding_action_type("off"), do: {:ok, "turn_off"}
  defp binding_action_type("toggle"), do: {:ok, "toggle_any_on"}
  defp binding_action_type("activate_scene"), do: {:ok, "activate_scene"}
  defp binding_action_type(_), do: {:error, :invalid_action}

  defp binding_action_config(device, %{"target_kind" => "all_groups"}) do
    if Picos.control_groups(device) == [] do
      {:error, :missing_target}
    else
      StoredActionConfig.normalize(%{"target_kind" => "all_groups"})
    end
  end

  defp binding_action_config(device, %{"target_kind" => "control_group", "target_id" => target_id}) do
    if Enum.any?(Picos.control_groups(device), &(&1["id"] == target_id)) do
      StoredActionConfig.normalize(%{"target_kind" => "control_group", "target_id" => target_id})
    else
      {:error, :missing_target}
    end
  end

  defp binding_action_config(device, %{"target_kind" => "scene", "target_id" => target_id}) do
    scene_id = Util.parse_optional_integer(target_id)

    if is_integer(device.room_id) and Targets.scene_exists_in_room?(device.room_id, scene_id) do
      StoredActionConfig.normalize(%{"target_kind" => "scene", "target_id" => scene_id})
    else
      {:error, :missing_target}
    end
  end

  defp binding_action_config(_device, _attrs), do: {:error, :missing_target}

  defp validate_five_button_device(%PicoDevice{hardware_profile: "5_button", buttons: buttons}) do
    if length(buttons) == 5, do: :ok, else: {:error, :invalid_button_layout}
  end

  defp validate_five_button_device(_device), do: {:error, :unsupported_hardware_profile}

  defp buttons_by_slot(%PicoDevice{} = device) do
    device.buttons
    |> Enum.sort_by(& &1.slot_index)
    |> Map.new(&{&1.slot_index, &1})
  end

  defp normalize_saved_target(group_ids, light_ids) do
    %{
      "group_ids" => Targets.normalize_integer_ids(group_ids),
      "light_ids" => Targets.normalize_integer_ids(light_ids)
    }
  end
end
