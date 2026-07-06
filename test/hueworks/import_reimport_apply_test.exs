defmodule Hueworks.ImportReimportApplyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.ReimportApply
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, GroupLight, Light, Room}

  test "refreshes bridge-owned light fields without changing user-owned fields" do
    bridge = insert_bridge()
    room = insert_room("HueWorks Room")

    existing =
      insert_light(bridge, %{
        name: "Old Bridge Name",
        display_name: "User Name",
        source_id: "light.office",
        room_id: room.id,
        enabled: false,
        ha_export_mode: :switch,
        homekit_export_mode: :switch,
        supports_color: false,
        supports_temp: false,
        external_id: "old-uid"
      })

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office",
                     name: "New Bridge Name",
                     room_source_id: "bridge-room",
                     capabilities: %{color: true, color_temp: true},
                     metadata: %{"unique_id" => "new-uid"}
                   }
                 ],
                 rooms: [%{source_id: "bridge-room", name: "Bridge Room"}]
               }),
               %{lights: %{"light.office" => true}, groups: %{}, rooms: %{}}
             )

    refreshed = Repo.get!(Light, existing.id)

    assert refreshed.name == "New Bridge Name"
    assert refreshed.display_name == "User Name"
    assert refreshed.room_id == room.id
    assert refreshed.enabled == false
    assert refreshed.ha_export_mode == :switch
    assert refreshed.homekit_export_mode == :switch
    assert refreshed.supports_color == true
    assert refreshed.supports_temp == true
    assert refreshed.external_id == "new-uid"
  end

  test "creates selected new lights in the selected room and skips unselected lights" do
    bridge = insert_bridge()
    room = insert_room("Office")

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 rooms: [%{source_id: "room-office", name: "Office"}],
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office_display",
                     name: "Office Display",
                     room_source_id: "room-office",
                     metadata: %{"unique_id" => "display-uid"}
                   },
                   %{
                     source: :ha,
                     source_id: "light.ignored",
                     name: "Ignored",
                     room_source_id: "room-office",
                     metadata: %{"unique_id" => "ignored-uid"}
                   }
                 ]
               }),
               %{
                 lights: %{
                   "light.office_display" => %{"selected" => true, "target_room_id" => room.id},
                   "light.ignored" => false
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    created = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_display")

    assert created.name == "Office Display"
    assert created.room_id == room.id
    refute Repo.get_by(Light, bridge_id: bridge.id, source_id: "light.ignored")
  end

  test "refreshes group membership from normalized memberships" do
    bridge = insert_bridge()
    room = insert_room("Kitchen")
    light_a = insert_light(bridge, %{source_id: "light.a", room_id: room.id})
    light_b = insert_light(bridge, %{source_id: "light.b", room_id: room.id})

    group =
      insert_group(bridge, %{
        source_id: "group.kitchen",
        room_id: room.id,
        metadata: %{"members" => ["light.a"]}
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{source: :ha, source_id: "light.a", name: "Light A"},
                   %{source: :ha, source_id: "light.b", name: "Light B"}
                 ],
                 groups: [
                   %{source: :ha, source_id: "group.kitchen", name: "Kitchen Group"}
                 ],
                 memberships: %{
                   group_lights: [
                     %{group_source_id: "group.kitchen", light_source_id: "light.b"}
                   ]
                 }
               }),
               %{
                 lights: %{"light.a" => true, "light.b" => true},
                 groups: %{"group.kitchen" => true},
                 rooms: %{}
               }
             )

    assert Repo.all(from(gl in GroupLight, where: gl.group_id == ^group.id, select: gl.light_id)) ==
             [light_b.id]
  end

  test "deletes hidden duplicates that are absent upstream" do
    bridge = insert_bridge()
    canonical = insert_light(bridge, %{source_id: "light.real"})

    hidden =
      insert_light(bridge, %{
        source_id: "light.hidden",
        canonical_light_id: canonical.id,
        enabled: false,
        room_id: nil
      })

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{lights: %{}, groups: %{}, rooms: %{}}
             )

    refute Repo.get(Light, hidden.id)
  end

  test "delete resolution requires an expected external id safety token" do
    bridge = insert_bridge()
    light = insert_light(bridge, %{source_id: "light.delete", external_id: "delete-uid"})

    assert {:error, {:missing_expected_external_id, :light, "light.delete"}} =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{
                 lights: %{"light.delete" => %{"action" => "delete"}},
                 groups: %{},
                 rooms: %{}
               }
             )

    assert Repo.get(Light, light.id)
  end

  defp normalized(overrides) do
    %{
      rooms: [],
      lights: [],
      groups: [],
      memberships: %{}
    }
    |> Map.merge(overrides)
  end

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :ha,
      name: "Home Assistant",
      host: "10.0.0.2",
      credentials: %{"token" => "token"},
      import_complete: true,
      enabled: true
    }

    %Bridge{}
    |> Bridge.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_room(name), do: Repo.insert!(%Room{name: name})

  defp insert_light(bridge, attrs) do
    defaults = %{
      name: "Existing Light",
      source: :ha,
      source_id: "light.existing",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    %Light{}
    |> Light.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_group(bridge, attrs) do
    defaults = %{
      name: "Existing Group",
      source: :ha,
      source_id: "group.existing",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    %Hueworks.Schemas.Group{}
    |> Hueworks.Schemas.Group.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
