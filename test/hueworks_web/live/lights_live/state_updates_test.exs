defmodule HueworksWeb.LightsLive.StateUpdatesTest do
  use ExUnit.Case, async: true

  alias HueworksWeb.LightsLive.Actions.Result
  alias HueworksWeb.LightsLive.StateUpdates

  test "apply_action_result merges light attrs and updates status" do
    assigns = %{
      light_state: %{1 => %{power: :off, brightness: 25}},
      group_state: %{},
      active_scene_by_room: %{}
    }

    result = %Result{target_type: :light, target_id: 1, attrs: %{power: :on}, status: "Updated"}

    updated = StateUpdates.apply_action_result(assigns, result)

    assert updated.status == "Updated"
    assert updated.light_state[1] == %{power: :on, brightness: 25}
  end

  test "replace_control_state updates group state in place" do
    assigns = %{
      light_state: %{},
      group_state: %{2 => %{power: :off, brightness: 10}},
      active_scene_by_room: %{}
    }

    updated = StateUpdates.replace_control_state(assigns, :group, 2, %{power: :on})

    assert updated.group_state[2] == %{power: :on}
  end

  test "put_active_scene adds and removes room entries" do
    assigns = %{light_state: %{}, group_state: %{}, active_scene_by_room: %{4 => 9}}

    assert %{active_scene_by_room: %{4 => 11}} =
             StateUpdates.put_active_scene(assigns, 4, 11)

    assert %{active_scene_by_room: %{}} = StateUpdates.put_active_scene(assigns, 4, nil)
  end
end
