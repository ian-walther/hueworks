defmodule Hueworks.SchemasTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    BridgeImport,
    Group,
    GroupLight,
    Light,
    LightState,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :hue,
      name: "Hue Bridge",
      host: "192.168.1.2",
      credentials: %{"api_key" => "abc"},
      enabled: true,
      import_complete: false
    }

    Repo.insert!(struct(Bridge, Map.merge(defaults, attrs)))
  end

  defp insert_room(name \\ "Room") do
    Repo.insert!(%Room{name: name})
  end

  defp insert_light(bridge, attrs \\ %{}) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  defp insert_group(bridge, attrs \\ %{}) do
    defaults = %{
      name: "Group",
      source: :hue,
      source_id: "g1",
      bridge_id: bridge.id,
      metadata: %{}
    }

    Repo.insert!(struct(Group, Map.merge(defaults, attrs)))
  end

  test "bridge requires core fields and enforces unique type/host" do
    changeset = Bridge.changeset(%Bridge{}, %{})
    errors = errors_on(changeset)

    assert errors[:type] == ["can't be blank"]
    assert errors[:name] == ["can't be blank"]
    assert errors[:host] == ["can't be blank"]
    assert errors[:credentials] == ["can't be blank"]

    insert_bridge(%{type: :hue, host: "10.0.0.1"})

    {:error, dupe} =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Dupe",
        host: "10.0.0.1",
        credentials: %{"api_key" => "x"}
      })
      |> Repo.insert()

    refute dupe.valid?
    assert Map.has_key?(errors_on(dupe), :type) or Map.has_key?(errors_on(dupe), :host)
  end

  test "bridge import requires bridge_id, raw_blob, status, imported_at" do
    changeset = BridgeImport.changeset(%BridgeImport{}, %{})
    errors = errors_on(changeset)

    assert errors[:bridge_id] == ["can't be blank"]
    assert errors[:raw_blob] == ["can't be blank"]
    assert errors[:status] == ["can't be blank"]
    assert errors[:imported_at] == ["can't be blank"]
  end

  test "schemas accept z2m source/type values" do
    bridge_changeset =
      Bridge.changeset(%Bridge{}, %{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.90",
        credentials: %{"broker_port" => 1883}
      })

    assert bridge_changeset.valid?

    bridge = insert_bridge(%{type: :z2m, host: "10.0.0.91", name: "Z2M"})

    light_changeset =
      Light.changeset(%Light{}, %{
        name: "Z2M Light",
        source: :z2m,
        source_id: "strip.kitchen",
        bridge_id: bridge.id,
        actual_min_kelvin: 2100,
        actual_max_kelvin: 6100
      })

    assert light_changeset.valid?

    group_changeset =
      Group.changeset(%Group{}, %{
        name: "Z2M Group",
        source: :z2m,
        source_id: "group.kitchen",
        bridge_id: bridge.id,
        actual_min_kelvin: 2100,
        actual_max_kelvin: 6100
      })

    assert group_changeset.valid?
  end

  test "light requires core fields and forbids self canonical reference" do
    changeset = Light.changeset(%Light{}, %{})
    errors = errors_on(changeset)

    assert errors[:name] == ["can't be blank"]
    assert errors[:source] == ["can't be blank"]
    assert errors[:source_id] == ["can't be blank"]
    assert errors[:bridge_id] == ["can't be blank"]

    bridge = insert_bridge()
    light = insert_light(bridge)

    changeset = Light.changeset(light, %{canonical_light_id: light.id})
    errors = errors_on(changeset)
    assert errors[:canonical_light_id] == ["cannot reference itself"]
  end

  test "light actual kelvin is only supported for HA/Z2M sources" do
    bridge = insert_bridge(%{type: :hue})

    changeset =
      Light.changeset(%Light{}, %{
        name: "Light",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        actual_min_kelvin: 2000
      })

    errors = errors_on(changeset)
    assert errors[:actual_min_kelvin] == ["only supported for HA and Z2M entities"]
    assert errors[:actual_max_kelvin] == ["only supported for HA and Z2M entities"]
  end

  test "group requires core fields and forbids self references" do
    changeset = Group.changeset(%Group{}, %{})
    errors = errors_on(changeset)

    assert errors[:name] == ["can't be blank"]
    assert errors[:source] == ["can't be blank"]
    assert errors[:source_id] == ["can't be blank"]
    assert errors[:bridge_id] == ["can't be blank"]

    bridge = insert_bridge()
    group = insert_group(bridge)

    changeset = Group.changeset(group, %{parent_group_id: group.id})
    assert errors_on(changeset)[:parent_group_id] == ["cannot reference itself"]

    changeset = Group.changeset(group, %{canonical_group_id: group.id})
    assert errors_on(changeset)[:canonical_group_id] == ["cannot reference itself"]
  end

  test "group actual kelvin is only supported for HA/Z2M sources" do
    bridge = insert_bridge(%{type: :hue})

    changeset =
      Group.changeset(%Group{}, %{
        name: "Group",
        source: :hue,
        source_id: "g1",
        bridge_id: bridge.id,
        actual_min_kelvin: 2000
      })

    errors = errors_on(changeset)
    assert errors[:actual_min_kelvin] == ["only supported for HA and Z2M entities"]
    assert errors[:actual_max_kelvin] == ["only supported for HA and Z2M entities"]
  end

  test "room requires name" do
    changeset = Room.changeset(%Room{}, %{})
    assert errors_on(changeset)[:name] == ["can't be blank"]
  end

  test "scene requires name and room_id" do
    changeset = Scene.changeset(%Scene{}, %{})
    errors = errors_on(changeset)
    assert errors[:name] == ["can't be blank"]
    assert errors[:room_id] == ["can't be blank"]
  end

  test "scene_component requires scene_id and light_state_id" do
    changeset = SceneComponent.changeset(%SceneComponent{}, %{})
    errors = errors_on(changeset)
    assert errors[:scene_id] == ["can't be blank"]
    assert errors[:light_state_id] == ["can't be blank"]
  end

  test "light_state requires name and type" do
    changeset = LightState.changeset(%LightState{}, %{})
    errors = errors_on(changeset)
    assert errors[:name] == ["can't be blank"]
    assert errors[:type] == ["can't be blank"]
  end

  test "light_state circadian config is normalized and validated" do
    changeset =
      LightState.changeset(%LightState{}, %{
        name: "Circadian",
        type: :circadian,
        config: %{
          min_brightness: "15",
          max_brightness: "90",
          brightness_mode: "tanh",
          sunrise_time: "06:45"
        }
      })

    assert changeset.valid?
    assert get_change(changeset, :config)["min_brightness"] == 15
    assert get_change(changeset, :config)["max_brightness"] == 90
    assert get_change(changeset, :config)["brightness_mode"] == "tanh"
    assert get_change(changeset, :config)["sunrise_time"] == "06:45:00"
  end

  test "light_state circadian rejects unsupported config keys" do
    changeset =
      LightState.changeset(%LightState{}, %{
        name: "Circadian",
        type: :circadian,
        config: %{
          sleep_brightness: 1,
          prefer_rgb_color: true
        }
      })

    refute changeset.valid?
    errors = errors_on(changeset)
    assert "sleep_brightness is not supported" in errors[:config]
    assert "prefer_rgb_color is not supported" in errors[:config]
  end

  test "light_state manual config is normalized with default mode" do
    changeset =
      LightState.changeset(%LightState{}, %{
        name: "Manual",
        type: :manual,
        config: %{"temperature" => "3000", "custom" => "ok"}
      })

    assert changeset.valid?

    assert get_change(changeset, :config) == %{
             "mode" => "temperature",
             "temperature" => 3000,
             "custom" => "ok"
           }
  end

  test "light_state manual color config normalizes numeric values" do
    changeset =
      LightState.changeset(%LightState{}, %{
        name: "Color",
        type: :manual,
        config: %{"mode" => "color", "brightness" => "80", "hue" => "210", "saturation" => "60"}
      })

    assert changeset.valid?

    assert get_change(changeset, :config) == %{
             "mode" => "color",
             "brightness" => 80,
             "hue" => 210,
             "saturation" => 60
           }
  end

  test "light_state manual config accepts kelvin as an input alias" do
    changeset =
      LightState.changeset(%LightState{}, %{
        name: "Manual",
        type: :manual,
        config: %{kelvin: "3200"}
      })

    assert changeset.valid?

    assert get_change(changeset, :config) == %{
             "mode" => "temperature",
             "temperature" => 3200
           }
  end

  test "light_state manual_config returns canonical atom-keyed config" do
    config =
      LightState.manual_config(%{
        "mode" => "color",
        "brightness" => 80,
        "temperature" => 3000,
        "hue" => 210,
        "saturation" => 60,
        "custom" => "ignored"
      })

    assert config == %{
             mode: :color,
             brightness: 80,
             kelvin: 3000,
             hue: 210,
             saturation: 60
           }
  end

  test "light_state manual_mode returns canonical mode atoms" do
    assert LightState.manual_mode(%{"mode" => "color"}) == :color
    assert LightState.manual_mode(%{mode: :color}) == :color
    assert LightState.manual_mode(%{"temperature" => 3000}) == :temperature
  end

  test "light_state circadian_config returns a typed circadian config struct" do
    config =
      LightState.circadian_config(%{
        "min_brightness" => "15",
        "brightness_mode" => "linear",
        "sunrise_time" => "06:45"
      })

    assert %Hueworks.Circadian.Config{} = config
    assert config.min_brightness == 15
    assert config.brightness_mode == :linear
    assert config.sunrise_time == "06:45:00"
  end

  test "scene_component_light requires scene_component_id and light_id" do
    changeset = SceneComponentLight.changeset(%SceneComponentLight{}, %{})
    errors = errors_on(changeset)
    assert errors[:scene_component_id] == ["can't be blank"]
    assert errors[:light_id] == ["can't be blank"]

    valid_changeset =
      SceneComponentLight.changeset(%SceneComponentLight{}, %{
        scene_component_id: 1,
        light_id: 2,
        default_power: :force_off
      })

    assert valid_changeset.valid?
    assert get_change(valid_changeset, :default_power) == :force_off
  end

  test "group_light requires group_id and light_id" do
    changeset = GroupLight.changeset(%GroupLight{}, %{})
    errors = errors_on(changeset)
    assert errors[:group_id] == ["can't be blank"]
    assert errors[:light_id] == ["can't be blank"]
  end

  test "light enforces unique bridge/source_id" do
    bridge = insert_bridge(%{host: "10.0.0.2"})
    insert_light(bridge, %{source_id: "1"})

    {:error, changeset} =
      %Light{}
      |> Light.changeset(%{name: "Dup", source: :hue, source_id: "1", bridge_id: bridge.id})
      |> Repo.insert()

    refute changeset.valid?
    assert Map.has_key?(errors_on(changeset), :bridge_id)
  end

  test "group enforces unique bridge/source_id" do
    bridge = insert_bridge(%{host: "10.0.0.3"})
    insert_group(bridge, %{source_id: "g1"})

    {:error, changeset} =
      %Group{}
      |> Group.changeset(%{name: "Dup", source: :hue, source_id: "g1", bridge_id: bridge.id})
      |> Repo.insert()

    refute changeset.valid?
    assert Map.has_key?(errors_on(changeset), :bridge_id)
  end

  test "scene_component_light and group_light changesets accept valid data" do
    bridge = insert_bridge(%{host: "10.0.0.4"})
    room = insert_room()
    light = insert_light(bridge, %{source_id: "1", room_id: room.id})
    group = insert_group(bridge, %{source_id: "g1", room_id: room.id})

    light_state = Repo.insert!(%LightState{name: "State", type: :manual})
    scene = Repo.insert!(%Scene{name: "Scene", room_id: room.id})
    component = Repo.insert!(%SceneComponent{scene_id: scene.id, light_state_id: light_state.id})

    assert %SceneComponentLight{} =
             Repo.insert!(
               SceneComponentLight.changeset(%SceneComponentLight{}, %{
                 scene_component_id: component.id,
                 light_id: light.id
               })
             )

    assert %GroupLight{} =
             Repo.insert!(
               GroupLight.changeset(%GroupLight{}, %{group_id: group.id, light_id: light.id})
             )
  end
end
