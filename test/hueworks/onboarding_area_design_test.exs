defmodule Hueworks.Onboarding.AreaDesignTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.Onboarding.AreaDesign
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Area,
    BridgeImport,
    ExternalSpaceMapping,
    Light
  }

  setup do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{token: "token"}
      })

    snapshot = %{
      external_spaces: [
        %{kind: "ha_floor", external_id: "floor-1", name: "First Floor"},
        %{
          kind: "ha_area",
          external_id: "office",
          name: "Office",
          parent_kind: "ha_floor",
          parent_external_id: "floor-1"
        },
        %{
          kind: "ha_area",
          external_id: "kitchen",
          name: "Kitchen",
          parent_kind: "ha_floor",
          parent_external_id: "floor-1"
        },
        %{kind: "ha_area", external_id: "garage", name: "Garage"}
      ],
      areas: [],
      lights: [
        %{source_id: "light.office", space_refs: [%{kind: "ha_area", external_id: "office"}]},
        %{source_id: "light.kitchen", space_refs: [%{kind: "ha_area", external_id: "kitchen"}]},
        %{source_id: "light.garage", space_refs: [%{kind: "ha_area", external_id: "garage"}]}
      ],
      groups: []
    }

    Repo.insert!(%BridgeImport{
      bridge_id: bridge.id,
      raw_blob: %{"floors" => [], "areas" => [], "config_entries" => []},
      normalized_blob: snapshot,
      review_blob: %{},
      status: :normalized,
      imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    %{bridge: bridge}
  end

  test "refresh persists inventory spaces without materializing HA entities", %{bridge: bridge} do
    assert {:ok, design} = AreaDesign.refresh(bridge)

    assert length(design.floors) == 1
    assert length(design.unfloored_areas) == 1
    assert Repo.aggregate(Light, :count) == 0

    floor = hd(design.floors)
    assert floor.space.external_id == "floor-1"
    assert Enum.map(floor.children, & &1.space.external_id) == ["kitchen", "office"]
    assert floor.entity_count == 2
    assert hd(design.unfloored_areas).entity_count == 1
  end

  test "using one Floor as one Area maps the Floor and every child without moving lights", %{
    bridge: bridge
  } do
    existing_area = Repo.insert!(%Area{name: "Existing"})

    existing_light =
      Repo.insert!(%Light{
        name: "Already placed",
        source: :ha,
        source_id: "light.existing",
        bridge_id: bridge.id,
        area_id: existing_area.id
      })

    {:ok, _design} = AreaDesign.refresh(bridge)

    assert {:ok, main_floor} =
             AreaDesign.use_floor_as_one_area(bridge, "floor-1", %{name: "Main Floor"})

    assert mapping_count(main_floor.id) == 3
    assert Repo.reload(existing_light).area_id == existing_area.id

    assert {:ok, repeated} =
             AreaDesign.use_floor_as_one_area(bridge, "floor-1", %{name: "Main Floor"})

    assert repeated.id == main_floor.id
    assert Repo.aggregate(Area, :count) == 2
  end

  test "using child HA Areas separately creates and maps each child but not the Floor", %{
    bridge: bridge
  } do
    {:ok, _design} = AreaDesign.refresh(bridge)

    assert {:ok, areas} = AreaDesign.use_floor_areas_separately(bridge, "floor-1")
    assert Enum.map(areas, & &1.name) |> Enum.sort() == ["Kitchen", "Office"]
    assert Repo.aggregate(ExternalSpaceMapping, :count) == 2

    refute mapped?(bridge.id, "ha_floor", "floor-1")
    assert mapped?(bridge.id, "ha_area", "office")
    assert mapped?(bridge.id, "ha_area", "kitchen")

    assert {:ok, repeated} = AreaDesign.use_floor_areas_separately(bridge, "floor-1")
    assert Enum.map(repeated, & &1.id) |> Enum.sort() == Enum.map(areas, & &1.id) |> Enum.sort()
    assert Repo.aggregate(Area, :count) == 2
  end

  test "individual spaces can converge on an existing Area or be explicitly skipped", %{
    bridge: bridge
  } do
    destination = Repo.insert!(%Area{name: "Main Floor"})
    {:ok, _design} = AreaDesign.refresh(bridge)

    assert {:ok, _mapping} = AreaDesign.map_space(bridge, "ha_area", "office", destination.id)
    assert {:ok, _mapping} = AreaDesign.map_space(bridge, "ha_area", "kitchen", destination.id)
    assert mapping_count(destination.id) == 2

    assert :ok = AreaDesign.skip_space(bridge, "ha_area", "office")
    refute mapped?(bridge.id, "ha_area", "office")
    assert mapped?(bridge.id, "ha_area", "kitchen")
  end

  defp mapping_count(area_id) do
    import Ecto.Query
    Repo.aggregate(from(m in ExternalSpaceMapping, where: m.area_id == ^area_id), :count)
  end

  defp mapped?(bridge_id, kind, external_id) do
    import Ecto.Query

    Repo.exists?(
      from(m in ExternalSpaceMapping,
        join: space in assoc(m, :external_space),
        where:
          space.bridge_id == ^bridge_id and space.kind == ^kind and
            space.external_id == ^external_id
      )
    )
  end
end
