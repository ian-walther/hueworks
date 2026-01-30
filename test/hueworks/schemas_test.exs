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
      |> Bridge.changeset(%{type: :hue, name: "Dupe", host: "10.0.0.1", credentials: %{"api_key" => "x"}})
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

  test "light actual kelvin is only supported for HA sources" do
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
    assert errors[:actual_min_kelvin] == ["only supported for HA entities"]
    assert errors[:actual_max_kelvin] == ["only supported for HA entities"]
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

  test "group actual kelvin is only supported for HA sources" do
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
    assert errors[:actual_min_kelvin] == ["only supported for HA entities"]
    assert errors[:actual_max_kelvin] == ["only supported for HA entities"]
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

  test "scene_component_light requires scene_component_id and light_id" do
    changeset = SceneComponentLight.changeset(%SceneComponentLight{}, %{})
    errors = errors_on(changeset)
    assert errors[:scene_component_id] == ["can't be blank"]
    assert errors[:light_id] == ["can't be blank"]
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
