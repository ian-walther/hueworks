defmodule HueworksWeb.PicoConfigLive.BindingEditorTest do
  use Hueworks.DataCase, async: true

  alias HueworksWeb.PicoConfigLive.BindingEditor

  test "missing control-group checkbox params clear the selection" do
    assigns = %{
      binding_action: "toggle",
      binding_target_kind: "control_groups",
      binding_target_id: nil,
      binding_target_group_ids: ["group-a"],
      control_groups: [
        %{"id" => "group-a", "name" => "Overhead"},
        %{"id" => "group-b", "name" => "Lamps"}
      ]
    }

    assert %{
             binding_action: "toggle",
             binding_target_kind: "control_groups",
             binding_target_group_ids: []
           } = BindingEditor.update_assigns(assigns, %{"action" => "toggle"})
  end

  test "scene editor changes preserve the prior control-group selection" do
    assigns = %{
      binding_action: "toggle",
      binding_target_kind: "control_groups",
      binding_target_id: nil,
      binding_target_group_ids: ["group-a"],
      control_groups: [%{"id" => "group-a", "name" => "Overhead"}]
    }

    assert %{
             binding_action: "activate_scene",
             binding_target_kind: "scene",
             binding_target_group_ids: ["group-a"]
           } = BindingEditor.update_assigns(assigns, %{"action" => "activate_scene"})
  end

  test "control-group selections survive a scene-mode round trip" do
    assigns = %{
      binding_action: "toggle",
      binding_target_kind: "control_groups",
      binding_target_id: nil,
      binding_target_group_ids: ["group-a"],
      control_groups: [
        %{"id" => "group-a", "name" => "Overhead"},
        %{"id" => "group-b", "name" => "Lamps"}
      ]
    }

    scene_assigns =
      assigns
      |> Map.merge(BindingEditor.update_assigns(assigns, %{"action" => "activate_scene"}))
      |> Map.put(:binding_target_id, 1)

    assert %{
             binding_action: "toggle",
             binding_target_kind: "control_groups",
             binding_target_group_ids: ["group-a"]
           } = BindingEditor.update_assigns(scene_assigns, %{"action" => "toggle"})
  end

  test "current binding and validation share the same normalized shape" do
    assigns = %{
      binding_action: "off",
      binding_target_kind: "control_groups",
      binding_target_id: nil,
      binding_target_group_ids: ["group-a"]
    }

    binding = BindingEditor.current_binding(assigns)

    assert binding == %{
             "action" => "off",
             "target_kind" => "control_groups",
             "target_id" => nil,
             "target_ids" => ["group-a"]
           }

    assert BindingEditor.valid_learning_binding?(
             binding,
             [%{"id" => "group-a", "name" => "Overhead"}],
             []
           )

    refute BindingEditor.valid_learning_binding?(
             %{binding | "target_ids" => []},
             [%{"id" => "group-a", "name" => "Overhead"}],
             []
           )
  end
end
