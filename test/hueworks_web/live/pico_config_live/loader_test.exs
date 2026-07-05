defmodule HueworksWeb.PicoConfigLive.LoaderTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Schemas.{PicoDevice, Room}
  alias HueworksWeb.PicoConfigLive.Loader

  test "reload_from_devices keeps a valid selected pico and resets detect mode on detail pages" do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.740",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "office-pico",
        name: "Office Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        live_action: :show,
        bridge: bridge,
        detect_pico_mode: true,
        clone_source_pico_id: nil,
        selected_control_group_id: "group-a",
        binding_action: "toggle",
        binding_target_id: nil,
        binding_target_group_ids: ["group-a"]
      }
    }

    socket =
      Loader.reload_from_devices(socket, Picos.list_devices_for_bridge(bridge.id), device.id)

    assert socket.assigns.selected_pico.id == device.id
    refute socket.assigns.detect_pico_mode
    assert socket.assigns.control_group_name == "Overhead"
    assert socket.assigns.binding_target_group_ids == ["group-a"]
  end
end
