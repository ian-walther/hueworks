defmodule HueworksWeb.EntityControlComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HueworksWeb.EntityControlComponents

  test "inline controls preserve the slider hook and id contract" do
    target = %{
      id: 42,
      supports_temp: true,
      supports_color: true,
      min_kelvin: 2000,
      max_kelvin: 6500
    }

    state_map = %{42 => %{brightness: 61, kelvin: 3100, hue: 125, saturation: 72}}

    html =
      render_component(&EntityControlComponents.controls/1,
        target: target,
        target_type: :light,
        state_map: state_map,
        disabled: true
      )

    assert html =~ ~s(id="light-level-42")
    assert html =~ ~s(phx-hook="BrightnessSlider")
    assert html =~ ~s(data-output-id="light-brightness-value-42")
    assert html =~ ~s(id="light-temp-42")
    assert html =~ ~s(id="light-hue-42")
    assert html =~ ~s(data-saturation-input-id="light-saturation-42")
    assert html =~ ~s(id="light-saturation-42")
    assert html =~ "disabled"
  end

  test "modal controls use the control page id contract and hide unsupported controls" do
    target = %{id: 7, supports_temp: false, supports_color: false}

    html =
      render_component(&EntityControlComponents.controls/1,
        target: target,
        target_type: :group,
        state_map: %{7 => %{brightness: 45}},
        variant: :modal
      )

    assert html =~ ~s(id="control-group-brightness-7")
    assert html =~ ~s(id="control-group-brightness-value-7")
    refute html =~ "control-group-temp-7"
    refute html =~ "control-group-hue-7"
  end
end
