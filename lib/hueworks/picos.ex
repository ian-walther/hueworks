defmodule Hueworks.Picos do
  @moduledoc """
  Pico sync, configuration, and runtime action helpers.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, State}
  alias Hueworks.Groups
  alias Hueworks.Import.Fetch.Caseta
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, PicoButton, PicoDevice}
  alias Hueworks.Util
  alias Phoenix.PubSub

  @topic "pico_events"
  @five_button_preset "overhead_lamps_all_toggle"
  def topic, do: @topic

  def list_devices_for_bridge(bridge_id) when is_integer(bridge_id) do
    Repo.all(
      from(pd in PicoDevice,
        where: pd.bridge_id == ^bridge_id,
        order_by: [asc: pd.name]
      )
    )
    |> Repo.preload([:room, buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])])
  end

  def get_device(id) when is_integer(id) do
    PicoDevice
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      device ->
        Repo.preload(device, [
          :room,
          buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])
        ])
    end
  end

  def sync_bridge_picos(%Bridge{type: :caseta} = bridge) do
    raw = caseta_fetch_module().fetch_for_bridge(bridge)
    sync_bridge_picos(bridge, raw)
  rescue
    error -> {:error, Exception.message(error)}
  end

  def sync_bridge_picos(%Bridge{} = bridge, raw) when is_map(raw) do
    pico_buttons = Map.get(raw, :pico_buttons) || Map.get(raw, "pico_buttons") || []
    lights = Map.get(raw, :lights) || Map.get(raw, "lights") || []

    room_by_area_id = room_ids_by_area_id(bridge.id, lights)

    grouped =
      Enum.group_by(
        pico_buttons,
        &to_string(Map.get(&1, :parent_device_id) || Map.get(&1, "parent_device_id"))
      )

    Repo.transaction(fn ->
      existing_devices =
        Repo.all(from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id))
        |> Map.new(&{&1.source_id, &1})

      seen_device_ids =
        Enum.reduce(grouped, MapSet.new(), fn {device_source_id, buttons}, seen ->
          if device_source_id in [nil, ""] do
            seen
          else
            device =
              upsert_device(
                bridge,
                existing_devices[device_source_id],
                device_source_id,
                buttons,
                room_by_area_id
              )

            upsert_buttons(device, buttons)
            MapSet.put(seen, device_source_id)
          end
        end)

      stale_ids =
        existing_devices
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(seen_device_ids, &1))

      if stale_ids != [] do
        Repo.delete_all(
          from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id and pd.source_id in ^stale_ids)
        )
      end

      :ok
    end)

    {:ok, list_devices_for_bridge(bridge.id)}
  end

  def list_room_targets(room_id) when is_integer(room_id) do
    lights =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          order_by: [asc: l.name]
        )
      )

    groups =
      Repo.all(
        from(g in Group,
          where: g.room_id == ^room_id and is_nil(g.canonical_group_id),
          order_by: [asc: g.name]
        )
      )

    {groups, lights}
  end

  def set_device_room(%PicoDevice{} = device, room_id) do
    detected_room_id = auto_detected_room_id(device)
    room_id = Util.parse_optional_integer(room_id)
    metadata = device.metadata || %{}

    attrs =
      case room_id do
        nil ->
          %{
            room_id: detected_room_id,
            metadata:
              metadata
              |> Map.put("room_override", false)
          }

        room_id ->
          %{
            room_id: room_id,
            metadata:
              metadata
              |> Map.put("room_override", true)
          }
      end

    device
    |> PicoDevice.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, get_device(updated.id)}
      other -> other
    end
  end

  def control_groups(%PicoDevice{} = device) do
    device
    |> Map.get(:metadata, %{})
    |> Map.get("control_groups", [])
    |> normalize_control_groups()
  end

  def clone_device_config(%PicoDevice{} = destination, %PicoDevice{} = source) do
    destination = get_device(destination.id)
    source = get_device(source.id)

    cond do
      is_nil(destination) or is_nil(source) ->
        {:error, :device_not_found}

      destination.id == source.id ->
        {:error, :same_device}

      destination.bridge_id != source.bridge_id ->
        {:error, :different_bridge}

      not is_integer(source.room_id) ->
        {:error, :missing_source_room}

      true ->
        cloned_groups = clone_control_groups(source)
        group_id_map = Map.new(cloned_groups, &{&1["source_id"], &1["id"]})

        Repo.transaction(fn ->
          destination
          |> PicoDevice.changeset(%{room_id: source.room_id})
          |> Repo.update!()

          update_device_metadata!(destination, fn metadata ->
            metadata
            |> Map.put("control_groups", Enum.map(cloned_groups, &Map.drop(&1, ["source_id"])))
            |> Map.put("room_override", true)
          end)

          destination_buttons =
            Repo.all(
              from(pb in PicoButton,
                where: pb.pico_device_id == ^destination.id
              )
            )

          source_buttons =
            Repo.all(
              from(pb in PicoButton,
                where: pb.pico_device_id == ^source.id
              )
            )

          source_by_button_number =
            Map.new(source_buttons, &{&1.button_number, &1})

          Enum.each(destination_buttons, fn destination_button ->
            source_button = Map.get(source_by_button_number, destination_button.button_number)

            attrs =
              case source_button do
                nil ->
                  %{action_type: nil, action_config: %{}, enabled: true}

                %PicoButton{} ->
                  %{
                    action_type: source_button.action_type,
                    action_config:
                      clone_action_config(
                        source_button.action_config || %{},
                        group_id_map,
                        source.room_id
                      ),
                    enabled: source_button.enabled
                  }
              end

            destination_button
            |> PicoButton.changeset(attrs)
            |> Repo.update!()
          end)
        end)

        {:ok, get_device(destination.id)}
    end
  end

  def save_control_group(%PicoDevice{} = device, attrs) when is_map(attrs) do
    with room_id when is_integer(room_id) <- device.room_id,
         name when is_binary(name) and name != "" <- String.trim(attrs["name"] || ""),
         group_id <- attrs["id"] || Ecto.UUID.generate() do
      group_ids = normalize_integer_ids(attrs["group_ids"])
      light_ids = normalize_integer_ids(attrs["light_ids"])

      if valid_room_targets?(room_id, group_ids, light_ids) do
        updated_groups =
          device
          |> control_groups()
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

  def delete_control_group(%PicoDevice{} = device, group_id) when is_binary(group_id) do
    control_groups = Enum.reject(control_groups(device), &(&1["id"] == group_id))

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

    {:ok, get_device(device.id)}
  end

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
    |> PicoButton.changeset(%{
      action_type: nil,
      action_config: %{},
      enabled: true
    })
    |> Repo.update()
  end

  def save_five_button_preset(%PicoDevice{} = device, attrs) when is_map(attrs) do
    device = Repo.preload(device, buttons: from(pb in PicoButton, order_by: [asc: pb.slot_index]))

    with :ok <- validate_five_button_device(device),
         room_id when is_integer(room_id) <- device.room_id do
      primary =
        expand_room_targets(room_id, attrs["primary_group_ids"], attrs["primary_light_ids"])

      secondary =
        expand_room_targets(room_id, attrs["secondary_group_ids"], attrs["secondary_light_ids"])

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

      {:ok, get_device(device.id)}
    else
      nil -> {:error, :missing_room}
      {:error, _} = error -> error
    end
  end

  def save_five_button_preset(_device, _attrs), do: {:error, :invalid_device}

  def handle_button_press(bridge_id, button_source_id)
      when is_integer(bridge_id) and is_binary(button_source_id) do
    Logger.info(
      "[pico-trace] handle_button_press_start bridge_id=#{bridge_id} button_source_id=#{inspect(button_source_id)}"
    )

    button =
      Repo.one(
        from(pb in PicoButton,
          join: pd in PicoDevice,
          on: pd.id == pb.pico_device_id,
          where: pd.bridge_id == ^bridge_id and pb.source_id == ^button_source_id,
          preload: [pico_device: pd]
        )
      )

    case button do
      nil ->
        Logger.warning(
          "[pico-trace] handle_button_press_missing_mapping bridge_id=#{bridge_id} button_source_id=#{inspect(button_source_id)}"
        )

        :ignored

      %PicoButton{} = button ->
        timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

        button
        |> PicoButton.changeset(%{last_pressed_at: timestamp})
        |> Repo.update!()

        broadcast_press(button.pico_device_id, button.source_id)

        result =
          if button.enabled do
            execute_button_action(button)
          else
            Logger.info(
              "[pico-trace] handle_button_press_ignored bridge_id=#{bridge_id} button_source_id=#{inspect(button_source_id)} reason=:button_disabled"
            )

            :ignored
          end

        Logger.info(
          "[pico-trace] handle_button_press_complete bridge_id=#{bridge_id} pico_device_id=#{button.pico_device_id} button_source_id=#{inspect(button.source_id)} button_number=#{inspect(button.button_number)} slot_index=#{inspect(button.slot_index)} slot_label=#{inspect(button_slot_label(button.pico_device, button.slot_index))} binding=#{inspect(button_binding_summary(button, button.pico_device))} action_type=#{inspect(button.action_type)} action_config=#{inspect(button.action_config)} result=#{inspect(result)}"
        )

        result
    end
  end

  def button_slot_label(_device, slot_index), do: "Button #{slot_index + 1}"

  def button_binding_summary(%PicoButton{} = button, %PicoDevice{} = device) do
    case {button.action_type, button.action_config || %{}} do
      {nil, _} ->
        "Not assigned"

      {action_type, %{"target_kind" => "all_groups"}} ->
        "#{binding_action_label(action_type)} All Control Groups"

      {action_type, %{"target_kind" => "control_group", "target_id" => target_id}} ->
        target_name =
          device
          |> control_groups()
          |> Enum.find_value("Unknown Group", fn group ->
            if group["id"] == target_id, do: group["name"], else: nil
          end)

        "#{binding_action_label(action_type)} #{target_name}"

      {action_type, config} when is_map_key(config, "light_ids") ->
        "#{binding_action_label(action_type)} Custom Lights"

      {action_type, _config} ->
        binding_action_label(action_type)
    end
  end

  def room_override?(%PicoDevice{} = device) do
    Map.get(device.metadata || %{}, "room_override") == true
  end

  def auto_detected_room_id(%PicoDevice{} = device) do
    (device.metadata || %{})
    |> Map.get("detected_room_id")
    |> Util.parse_optional_integer()
  end

  defp upsert_device(bridge, existing, source_id, buttons, room_by_area_id) do
    sample = List.first(buttons) || %{}
    area_id = normalize_source_id(Map.get(sample, :area_id) || Map.get(sample, "area_id"))
    detected_room_id = Map.get(room_by_area_id, area_id)
    hardware_profile = hardware_profile(buttons)
    name = Map.get(sample, :device_name) || Map.get(sample, "device_name") || "Pico"

    room_id =
      cond do
        existing && room_override?(existing) -> existing.room_id
        true -> detected_room_id
      end

    metadata =
      (if(existing, do: existing.metadata, else: %{}) || %{})
      |> Map.put("area_id", area_id)
      |> Map.put("detected_room_id", detected_room_id)
      |> Map.put_new("room_override", false)

    attrs = %{
      bridge_id: bridge.id,
      room_id: room_id,
      source_id: source_id,
      name: name,
      hardware_profile: hardware_profile,
      enabled: true,
      metadata: metadata
    }

    case existing do
      nil ->
        %PicoDevice{}
        |> PicoDevice.changeset(attrs)
        |> Repo.insert!()

      device ->
        device
        |> PicoDevice.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp upsert_buttons(device, buttons) do
    existing_buttons =
      Repo.all(from(pb in PicoButton, where: pb.pico_device_id == ^device.id))
      |> Map.new(&{&1.source_id, &1})

    normalized_buttons =
      buttons
      |> Enum.map(fn button ->
        %{
          source_id:
            normalize_source_id(Map.get(button, :button_id) || Map.get(button, "button_id")),
          button_number:
            normalize_integer(Map.get(button, :button_number) || Map.get(button, "button_number"))
        }
      end)
      |> Enum.filter(fn button ->
        is_binary(button.source_id) and is_integer(button.button_number)
      end)
      |> Enum.sort_by(& &1.button_number)

    seen_button_ids =
      normalized_buttons
      |> Enum.with_index()
      |> Enum.reduce(MapSet.new(), fn {button, slot_index}, seen ->
        attrs = %{
          pico_device_id: device.id,
          source_id: button.source_id,
          button_number: button.button_number,
          slot_index: slot_index,
          enabled: true
        }

        case existing_buttons[button.source_id] do
          nil ->
            %PicoButton{}
            |> PicoButton.changeset(attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> PicoButton.changeset(attrs)
            |> Repo.update!()
        end

        MapSet.put(seen, button.source_id)
      end)

    stale_ids =
      existing_buttons
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(seen_button_ids, &1))

    if stale_ids != [] do
      Repo.delete_all(
        from(pb in PicoButton,
          where: pb.pico_device_id == ^device.id and pb.source_id in ^stale_ids
        )
      )
    end
  end

  defp room_ids_by_area_id(bridge_id, raw_lights) do
    room_id_by_zone_id =
      Repo.all(
        from(l in Light,
          where: l.bridge_id == ^bridge_id and l.source == :caseta,
          select: {l.source_id, l.room_id}
        )
      )
      |> Map.new()

    Enum.reduce(raw_lights, %{}, fn raw_light, acc ->
      zone_id = normalize_source_id(Map.get(raw_light, :zone_id) || Map.get(raw_light, "zone_id"))
      area_id = normalize_source_id(Map.get(raw_light, :area_id) || Map.get(raw_light, "area_id"))
      room_id = Map.get(room_id_by_zone_id, zone_id)

      if is_binary(area_id) and is_integer(room_id) do
        Map.put_new(acc, area_id, room_id)
      else
        acc
      end
    end)
  end

  defp hardware_profile(buttons) do
    case Enum.count(buttons) do
      5 -> "5_button"
      4 -> "4_button"
      2 -> "2_button"
      count -> "#{count}_button"
    end
  end

  defp validate_five_button_device(%PicoDevice{hardware_profile: "5_button", buttons: buttons}) do
    if length(buttons) == 5, do: :ok, else: {:error, :invalid_button_layout}
  end

  defp validate_five_button_device(_device), do: {:error, :unsupported_hardware_profile}

  defp expand_room_targets(room_id, group_ids, light_ids) do
    allowed_light_ids =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          select: l.id
        )
      )
      |> MapSet.new()

    group_light_ids =
      group_ids
      |> normalize_integer_ids()
      |> Enum.flat_map(fn group_id ->
        case Repo.one(from(g in Group, where: g.id == ^group_id, select: g.room_id)) do
          ^room_id -> Groups.member_light_ids(group_id)
          _ -> []
        end
      end)

    direct_light_ids =
      light_ids
      |> normalize_integer_ids()
      |> Enum.filter(&MapSet.member?(allowed_light_ids, &1))

    (group_light_ids ++ direct_light_ids)
    |> Enum.filter(&MapSet.member?(allowed_light_ids, &1))
    |> Enum.uniq()
  end

  defp buttons_by_slot(%PicoDevice{} = device) do
    device.buttons
    |> Enum.sort_by(& &1.slot_index)
    |> Map.new(&{&1.slot_index, &1})
  end

  defp normalize_saved_target(group_ids, light_ids) do
    %{
      "group_ids" => normalize_integer_ids(group_ids),
      "light_ids" => normalize_integer_ids(light_ids)
    }
  end

  defp execute_button_action(%PicoButton{action_type: nil}), do: :ignored

  defp execute_button_action(%PicoButton{pico_device: %{room_id: room_id}})
       when not is_integer(room_id) do
    Logger.warning("[pico-trace] execute_button_action_ignored reason=:missing_room")
    :ignored
  end

  defp execute_button_action(%PicoButton{
         action_type: "turn_on",
         pico_device: device,
         action_config: config
       }) do
    light_ids = action_light_ids(device, config)

    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=:on light_ids=#{inspect(light_ids)}"
    )

    _ = ManualControl.apply_power_action(device.room_id, light_ids, :on)
    :handled
  end

  defp execute_button_action(%PicoButton{
         action_type: "turn_off",
         pico_device: device,
         action_config: config
       }) do
    light_ids = action_light_ids(device, config)

    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=:off light_ids=#{inspect(light_ids)}"
    )

    _ = ManualControl.apply_power_action(device.room_id, light_ids, :off)
    :handled
  end

  defp execute_button_action(%PicoButton{
         action_type: "toggle_any_on",
         pico_device: device,
         action_config: config
       }) do
    light_ids = action_light_ids(device, config)
    any_on? = Enum.any?(light_ids, &light_powered?/1)

    action =
      if any_on? do
        :off
      else
        :on
      end

    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=#{inspect(action)} light_ids=#{inspect(light_ids)} any_on?=#{any_on?}"
    )

    _ = ManualControl.apply_power_action(device.room_id, light_ids, action)
    :handled
  end

  defp execute_button_action(button) do
    Logger.info(
      "[pico-trace] execute_button_action_ignored action_type=#{inspect(button.action_type)}"
    )

    :ignored
  end

  defp action_light_ids(_device, %{"light_ids" => light_ids}) when is_list(light_ids) do
    normalize_integer_ids(light_ids)
  end

  defp action_light_ids(device, %{"target_kind" => "all_groups"}) do
    device
    |> control_groups()
    |> Enum.flat_map(&control_group_light_ids(device.room_id, &1))
    |> Enum.uniq()
  end

  defp action_light_ids(device, %{"target_kind" => "control_group", "target_id" => target_id}) do
    device
    |> control_groups()
    |> Enum.find(&(Map.get(&1, "id") == target_id))
    |> case do
      nil -> []
      group -> control_group_light_ids(device.room_id, group)
    end
  end

  defp action_light_ids(_device, _config), do: []

  defp light_powered?(light_id) do
    state = DesiredState.get(:light, light_id) || State.get(:light, light_id) || %{}
    Map.get(state, :power) == :on
  end

  defp broadcast_press(pico_device_id, button_source_id) do
    PubSub.broadcast(
      Hueworks.PubSub,
      @topic,
      {:pico_button_press, pico_device_id, button_source_id}
    )
  end

  defp normalize_integer_ids(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_integer(value) ->
        [value]

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> [parsed]
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp binding_action_type("on"), do: {:ok, "turn_on"}
  defp binding_action_type("off"), do: {:ok, "turn_off"}
  defp binding_action_type("toggle"), do: {:ok, "toggle_any_on"}
  defp binding_action_type(_), do: {:error, :invalid_action}

  defp binding_action_label("turn_on"), do: "Turn On"
  defp binding_action_label("turn_off"), do: "Turn Off"
  defp binding_action_label("toggle_any_on"), do: "Toggle"
  defp binding_action_label(action), do: to_string(action)

  defp binding_action_config(device, %{"target_kind" => "all_groups"}) do
    if control_groups(device) == [] do
      {:error, :missing_target}
    else
      {:ok, %{"target_kind" => "all_groups"}}
    end
  end

  defp binding_action_config(device, %{"target_kind" => "control_group", "target_id" => target_id}) do
    if Enum.any?(control_groups(device), &(&1["id"] == target_id)) do
      {:ok, %{"target_kind" => "control_group", "target_id" => target_id}}
    else
      {:error, :missing_target}
    end
  end

  defp binding_action_config(_device, _attrs), do: {:error, :missing_target}

  defp valid_room_targets?(room_id, group_ids, light_ids) do
    allowed_light_ids =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          select: l.id
        )
      )
      |> MapSet.new()

    allowed_group_ids =
      Repo.all(
        from(g in Group,
          where: g.room_id == ^room_id and is_nil(g.canonical_group_id),
          select: g.id
        )
      )
      |> MapSet.new()

    Enum.all?(group_ids, &MapSet.member?(allowed_group_ids, &1)) and
      Enum.all?(light_ids, &MapSet.member?(allowed_light_ids, &1))
  end

  defp control_group_light_ids(room_id, %{"group_ids" => group_ids, "light_ids" => light_ids}) do
    expand_room_targets(room_id, group_ids, light_ids)
  end

  defp control_group_light_ids(_room_id, _group), do: []

  defp normalize_control_groups(groups) when is_list(groups) do
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
                normalize_integer_ids(Map.get(group, "group_ids") || Map.get(group, :group_ids)),
              "light_ids" =>
                normalize_integer_ids(Map.get(group, "light_ids") || Map.get(group, :light_ids))
            }
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp normalize_control_groups(_groups), do: []

  defp clone_control_groups(%PicoDevice{} = source) do
    source
    |> control_groups()
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

  defp clone_action_config(%{"target_kind" => "control_group", "target_id" => target_id}, group_id_map, room_id) do
    %{
      "target_kind" => "control_group",
      "target_id" => Map.get(group_id_map, target_id),
      "room_id" => room_id
    }
  end

  defp clone_action_config(%{"target_kind" => "all_groups"}, _group_id_map, room_id) do
    %{
      "target_kind" => "all_groups",
      "room_id" => room_id
    }
  end

  defp clone_action_config(%{"light_ids" => light_ids}, _group_id_map, room_id) do
    %{
      "light_ids" => normalize_integer_ids(light_ids),
      "room_id" => room_id
    }
  end

  defp clone_action_config(_config, _group_id_map, _room_id), do: %{}

  defp update_device_metadata(%PicoDevice{} = device, fun) when is_function(fun, 1) do
    device
    |> PicoDevice.changeset(%{metadata: fun.(device.metadata || %{})})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, get_device(updated.id)}
      other -> other
    end
  end

  defp update_device_metadata!(%PicoDevice{} = device, fun) when is_function(fun, 1) do
    device
    |> PicoDevice.changeset(%{metadata: fun.(device.metadata || %{})})
    |> Repo.update!()
  end

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: round(value)

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_source_id(value) when is_binary(value), do: value
  defp normalize_source_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_source_id(_value), do: nil

  defp caseta_fetch_module do
    Application.get_env(:hueworks, :caseta_pico_fetcher, Caseta)
  end
end
