defmodule Hueworks.Control.StateParserTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Control.StateParser

  test "power_map handles z2m uppercase values" do
    assert StateParser.power_map("ON") == %{power: :on}
    assert StateParser.power_map("OFF") == %{power: :off}
  end

  test "brightness_from_z2m treats brightness values as 0-254 scale" do
    assert StateParser.brightness_from_z2m(127) == %{brightness: 50}
    assert StateParser.brightness_from_z2m(78) == %{brightness: 31}
  end

  test "brightness_from_z2m_attrs prefers explicit brightness_percent when present" do
    attrs = %{"brightness" => 78, "brightness_percent" => 31}
    assert StateParser.brightness_from_z2m_attrs(attrs) == %{brightness: 31}
  end

  test "kelvin_from_z2m_attrs handles mired and kelvin payloads" do
    assert StateParser.kelvin_from_z2m_attrs(%{"color_temp" => 250}, nil) == %{kelvin: 4000}

    assert StateParser.kelvin_from_z2m_attrs(%{"color_temp_kelvin" => 2200}, nil) == %{
             kelvin: 2200
           }

    assert StateParser.kelvin_from_z2m_attrs(%{"color_temp" => 2200}, nil) == %{kelvin: 2200}
  end

  test "kelvin_from_z2m_attrs prefers extended color payload mapping below 2700K" do
    {x, y} = HomeAssistantPayload.extended_xy(2000)

    attrs = %{
      "color" => %{"x" => x, "y" => y},
      "color_temp" => 437
    }

    entity = %{extended_kelvin_range: true}

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 2000}
  end

  test "kelvin_from_z2m_attrs ignores xy payload when color_temp indicates normal white above 2700K" do
    {x, y} = HomeAssistantPayload.extended_xy(2200)

    attrs = %{
      "color" => %{"x" => x, "y" => y},
      "color_temp" => 3119
    }

    entity = %{extended_kelvin_range: true}

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 3119}
  end

  test "kelvin_from_z2m_attrs keeps midrange whites out of extended low-end band" do
    {x, y} = HomeAssistantPayload.extended_xy(2200)

    attrs = %{
      "color" => %{"x" => x, "y" => y},
      "color_temp" => 348
    }

    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert %{kelvin: kelvin} = StateParser.kelvin_from_z2m_attrs(attrs, entity)
    assert kelvin >= 2800
    assert kelvin <= 2950
  end

  test "kelvin_from_z2m_attrs remaps reported low-end floor when extended range is enabled" do
    attrs = %{"color_temp" => 437}

    entity = %{
      extended_kelvin_range: true,
      reported_min_kelvin: 2288,
      reported_max_kelvin: 6500
    }

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 2000}
  end

  test "kelvin_from_ha_attrs prefers extended xy payload mapping below 2700K" do
    {x, y} = HomeAssistantPayload.extended_xy(2000)

    attrs = %{
      "xy_color" => [x, y],
      "color_temp" => 437
    }

    entity = %{extended_kelvin_range: true}

    assert StateParser.kelvin_from_ha_attrs(attrs, entity) == %{kelvin: 2000}
  end

  test "kelvin_from_ha_attrs ignores xy payload when color_temp indicates normal white above 2700K" do
    {x, y} = HomeAssistantPayload.extended_xy(2200)

    attrs = %{
      "xy_color" => [x, y],
      "color_temp_kelvin" => 3119
    }

    entity = %{extended_kelvin_range: true}

    assert StateParser.kelvin_from_ha_attrs(attrs, entity) == %{kelvin: 3119}
  end

  test "kelvin_from_ha_attrs remaps reported low-end floor when extended range is enabled" do
    attrs = %{"color_temp_kelvin" => 2288}

    entity = %{
      extended_kelvin_range: true,
      reported_min_kelvin: 2288,
      reported_max_kelvin: 6500
    }

    assert StateParser.kelvin_from_ha_attrs(attrs, entity) == %{kelvin: 2000}
  end
end
