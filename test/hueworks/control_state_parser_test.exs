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

  test "color_from_ha_attrs returns xy color when HA reports color mode" do
    assert StateParser.color_from_ha_attrs(%{
             "color_mode" => "xy",
             "xy_color" => [0.1234, 0.5678]
           }) == %{x: 0.1234, y: 0.5678}
  end

  test "color_from_ha_attrs can derive xy from hs_color payloads" do
    color = StateParser.color_from_ha_attrs(%{"color_mode" => "hs", "hs_color" => [210, 60]})
    assert is_float(color.x)
    assert is_float(color.y)
  end

  test "color_from_ha_attrs ignores xy when HA is in color_temp mode" do
    assert StateParser.color_from_ha_attrs(%{
             "color_mode" => "color_temp",
             "xy_color" => [0.1234, 0.5678],
             "color_temp_kelvin" => 3000
           }) == %{}
  end

  test "color_from_z2m_attrs returns xy color when z2m reports xy mode" do
    assert StateParser.color_from_z2m_attrs(%{
             "color_mode" => "xy",
             "color" => %{"x" => 0.2222, "y" => 0.3333}
           }) == %{x: 0.2222, y: 0.3333}
  end

  test "color_from_hue_event extracts xy color from Hue v2 light payloads" do
    assert StateParser.color_from_hue_event(%{
             "color" => %{"xy" => %{"x" => 0.4112, "y" => 0.321}}
           }) == %{x: 0.4112, y: 0.321}
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

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 3648}
  end

  test "kelvin_from_z2m_attrs prefers color_temp when color_mode says color_temp even if xy is present" do
    {x, y} = HomeAssistantPayload.extended_xy(2000)

    attrs = %{
      "color_mode" => "color_temp",
      "color" => %{"x" => x, "y" => y},
      "color_temp" => 434
    }

    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 3043}
  end

  test "kelvin_from_z2m_attrs prefers xy when color_mode says xy even if color_temp is present" do
    {x, y} = HomeAssistantPayload.extended_xy(2493)

    attrs = %{
      "color_mode" => "xy",
      "color" => %{"x" => x, "y" => y},
      "color_temp" => 375
    }

    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 2493}
  end

  test "kelvin_from_z2m_attrs prefers xy in the 2600-2700 crossover band even when color_mode says color_temp" do
    {x, y} = HomeAssistantPayload.extended_xy(2681)

    attrs = %{
      "color_mode" => "color_temp",
      "color" => %{"x" => x, "y" => y},
      "color_temp_kelvin" => 3479
    }

    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 2681}
  end

  test "kelvin_from_z2m_attrs preserves direct sub-2700 kelvin reports for extended range lights" do
    {x, y} = HomeAssistantPayload.extended_xy(2688)

    attrs = %{
      "color_mode" => "color_temp",
      "color" => %{"x" => x, "y" => y},
      "color_temp" => 2688
    }

    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 2688}
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

  test "kelvin_from_z2m_attrs matches mired-space remap for normal whites on extended-range entities" do
    attrs = %{"color_temp_kelvin" => 3125}

    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert StateParser.kelvin_from_z2m_attrs(attrs, entity) == %{kelvin: 3900}
  end
end
