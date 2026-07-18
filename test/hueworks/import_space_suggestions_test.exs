defmodule Hueworks.Import.SpaceSuggestionsTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.ExternalSpaces
  alias Hueworks.Import.SpaceSuggestions
  alias Hueworks.Repo
  alias Hueworks.Schemas.Area

  setup do
    ha_bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{token: "token"}
      })

    hue_bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "hue.home",
        credentials: %{api_key: "key"}
      })

    main_floor = Repo.insert!(%Area{name: "Main Floor"})
    upstairs = Repo.insert!(%Area{name: "Upstairs"})

    %{ha_bridge: ha_bridge, hue_bridge: hue_bridge, main_floor: main_floor, upstairs: upstairs}
  end

  test "full identifier coverage produces a confident source-space suggestion", context do
    map_ha_area(context.ha_bridge, "office", context.main_floor)

    result =
      SpaceSuggestions.build(
        context.hue_bridge,
        native_snapshot([native_light("1", "aa"), native_light("2", "bb")]),
        context.ha_bridge,
        ha_snapshot([
          ha_light("light.one", "aa", "office"),
          ha_light("light.two", "bb", "office")
        ])
      )

    suggestion = result.spaces[{"hue_area", "1"}]
    assert suggestion.status == :confident
    assert suggestion.matched_count == 2
    assert suggestion.member_count == 2
    assert suggestion.suggested_area_id == context.main_floor.id
    assert suggestion.preselect?
  end

  test "partial coverage remains an explicit confirmation rather than a preselection", context do
    map_ha_area(context.ha_bridge, "office", context.main_floor)

    result =
      SpaceSuggestions.build(
        context.hue_bridge,
        native_snapshot([native_light("1", "aa"), native_light("2", "unmatched")]),
        context.ha_bridge,
        ha_snapshot([ha_light("light.one", "aa", "office")])
      )

    suggestion = result.spaces[{"hue_area", "1"}]
    assert suggestion.status == :partial
    assert suggestion.matched_count == 1
    refute suggestion.preselect?
  end

  test "members mapped to different Areas produce a conflict", context do
    map_ha_area(context.ha_bridge, "office", context.main_floor)
    map_ha_area(context.ha_bridge, "bedroom", context.upstairs)

    result =
      SpaceSuggestions.build(
        context.hue_bridge,
        native_snapshot([native_light("1", "aa"), native_light("2", "bb")]),
        context.ha_bridge,
        ha_snapshot([
          ha_light("light.one", "aa", "office"),
          ha_light("light.two", "bb", "bedroom")
        ])
      )

    suggestion = result.spaces[{"hue_area", "1"}]
    assert suggestion.status == :conflict
    assert suggestion.suggested_area_id in [context.main_floor.id, context.upstairs.id]
    refute suggestion.preselect?
  end

  test "non-unique physical identifiers are disclosed as ambiguous", context do
    map_ha_area(context.ha_bridge, "office", context.main_floor)

    result =
      SpaceSuggestions.build(
        context.hue_bridge,
        native_snapshot([native_light("1", "aa")]),
        context.ha_bridge,
        ha_snapshot([
          ha_light("light.one", "aa", "office"),
          ha_light("light.two", "aa", "office")
        ])
      )

    match = result.entities["1"]
    suggestion = result.spaces[{"hue_area", "1"}]
    assert match.status == :ambiguous_identity
    assert suggestion.status == :ambiguous_identity
    refute suggestion.preselect?
  end

  defp map_ha_area(bridge, external_id, area) do
    {:ok, spaces} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: external_id, name: external_id}
      ])

    space = Enum.find(spaces, &(&1.external_id == external_id))
    {:ok, _mapping} = ExternalSpaces.put_mapping(space, area)
  end

  defp native_snapshot(lights) do
    %{
      external_spaces: [
        %{kind: "hue_area", external_id: "1", source_id: "1", name: "Office"}
      ],
      areas: [%{kind: "hue_area", external_id: "1", source_id: "1", name: "Office"}],
      lights: lights,
      groups: []
    }
  end

  defp native_light(source_id, mac) do
    %{
      source_id: source_id,
      area_source_id: "1",
      identifiers: %{"mac" => mac}
    }
  end

  defp ha_snapshot(lights), do: %{external_spaces: [], areas: [], lights: lights, groups: []}

  defp ha_light(source_id, mac, area_id) do
    %{
      source_id: source_id,
      identifiers: %{"mac" => mac},
      space_refs: [
        %{kind: "ha_area", external_id: area_id, relationship: "direct"}
      ]
    }
  end
end
