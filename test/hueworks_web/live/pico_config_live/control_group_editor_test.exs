defmodule HueworksWeb.PicoConfigLive.ControlGroupEditorTest do
  use Hueworks.DataCase, async: true

  alias HueworksWeb.PicoConfigLive.ControlGroupEditor

  test "load_selected_assigns resets transient editor selections around the selected group" do
    assigns = %{
      selected_control_group_id: "group-a",
      editing_control_group_name: true,
      selected_control_group_group_id: 10,
      selected_control_group_light_id: 20,
      control_groups: [
        %{
          "id" => "group-a",
          "name" => "Overhead",
          "group_ids" => [1],
          "light_ids" => [2]
        }
      ]
    }

    assert %{
             editing_control_group_name: false,
             control_group_name: "Overhead",
             control_group_name_draft: "Overhead",
             control_group_group_ids: [1],
             control_group_light_ids: [2],
             selected_control_group_group_id: nil,
             selected_control_group_light_id: nil
           } = ControlGroupEditor.load_selected_assigns(assigns)
  end

  test "next_name fills the first available generated name gap" do
    assert ControlGroupEditor.next_name([
             %{"name" => "Control Group 1"},
             %{"name" => "Reading"},
             %{"name" => "Control Group 3"}
           ]) == "Control Group 2"
  end
end
