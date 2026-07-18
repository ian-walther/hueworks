defmodule Hueworks.Subscription.HueEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, Area}
  alias Hueworks.Subscription.HueEventStream.Connection

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "SSE light events refresh stale indexes before applying state" do
    area = Repo.insert!(%Area{name: "Hue Area"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "10.0.0.90",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Desk Lamp",
        source: :hue,
        source_id: "11",
        bridge_id: bridge.id,
        area_id: area.id
      })

    ref = make_ref()

    state = %{
      bridge: bridge,
      ref: ref,
      async_response: %HTTPoison.AsyncResponse{id: ref},
      buffer: "",
      lights_by_id: %{},
      groups_by_id: %{},
      group_light_ids: %{},
      group_lights: %{},
      last_refresh_at: System.monotonic_time(:millisecond) - 3_000
    }

    event = %{
      "type" => "light",
      "id_v1" => "/lights/#{light.source_id}",
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => 72.0}
    }

    chunk = "data: " <> Jason.encode!(event) <> "\n\n"

    assert {:noreply, updated_state} =
             Connection.handle_info(%HTTPoison.AsyncChunk{id: ref, chunk: chunk}, state)

    assert Map.has_key?(updated_state.lights_by_id, light.source_id)
    assert State.get(:light, light.id) == %{power: :on, brightness: 72}
  end
end
