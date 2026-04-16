defmodule HueworksWeb.LightsLive.EditFlowTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, Room}
  alias HueworksWeb.LightsLive.EditFlow

  test "open returns modal assigns for a saved light" do
    room = Repo.insert!(%Room{name: "Studio"})

    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.220",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Desk Lamp",
        source: :hue,
        source_id: "desk-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        display_name: "Desk Lamp",
        enabled: true
      })

    assert {:ok, assigns} = EditFlow.open("light", Integer.to_string(light.id))
    assert assigns.edit_modal_open == true
    assert assigns.edit_target_type == "light"
    assert assigns.edit_target_id == light.id
    assert assigns.edit_name == "Desk Lamp"
    assert assigns.edit_display_name == "Desk Lamp"
  end

  test "save updates the target and returns closed modal assigns merged with reloaded state" do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.221",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Floor Lamp",
        source: :hue,
        source_id: "floor-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        display_name: "Floor Lamp",
        enabled: true
      })

    assigns =
      EditFlow.close()
      |> Map.merge(%{
        edit_target_type: "light",
        edit_target_id: light.id,
        edit_modal_open: true,
        filter_session_id: nil
      })

    reload_fun = fn _assigns -> %{lights: [:reloaded], status: nil} end

    assert {:ok, updates} =
             EditFlow.save(assigns, %{"display_name" => "Reading Lamp"}, reload_fun)

    assert updates.edit_modal_open == false
    assert updates.lights == [:reloaded]
    assert updates.status == "Saved light Reading Lamp"
    assert Repo.get!(Light, light.id).display_name == "Reading Lamp"
  end

  test "run routes edit events through the shared edit flow" do
    assigns =
      EditFlow.close()
      |> Map.merge(%{
        edit_target_type: "light",
        edit_target_id: 123,
        edit_modal_open: true,
        edit_display_name: "Desk Lamp"
      })

    assert {:ok, %{edit_display_name: "Task Lamp"}} =
             EditFlow.run(
               "update_display_name",
               %{"display_name" => "Task Lamp"},
               assigns,
               fn current -> current end
             )

    assert {:ok, %{edit_show_link_selector: true}} =
             EditFlow.run("show_link_selector", %{}, assigns, fn current -> current end)

    assert {:ok, %{edit_modal_open: false}} =
             EditFlow.run("close_edit", %{}, assigns, fn current -> current end)
  end
end
