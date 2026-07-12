defmodule Hueworks.Control.TransitionPolicyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{Operation, TransitionPolicy}
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Room, Scene}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    :ok
  end

  test "manual policy uses the global transition and brightness scaling setting" do
    Repo.insert!(%AppSetting{
      scope: "global",
      default_transition_ms: 750,
      scale_transition_by_brightness: true
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    assert TransitionPolicy.manual() == %TransitionPolicy{
             duration_ms: 750,
             scaling: :brightness_delta
           }
  end

  test "circadian policy is fixed and unscaled" do
    assert TransitionPolicy.circadian() == %TransitionPolicy{
             duration_ms: 500,
             scaling: :none
           }
  end

  test "a legacy direct transition override is represented on its operation" do
    Repo.insert!(%AppSetting{
      scope: "global",
      default_transition_ms: 750,
      scale_transition_by_brightness: true
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    assert Operation.new(transition_ms: 1_200).transition_policy == %TransitionPolicy{
             duration_ms: 1_200,
             scaling: :brightness_delta
           }
  end

  test "scene activation uses a saved custom duration or a one-shot override" do
    scene = %Scene{activation_transition_ms: 30_000}

    assert TransitionPolicy.scene_activation(scene) == %TransitionPolicy{
             duration_ms: 30_000,
             scaling: :none
           }

    assert TransitionPolicy.scene_activation(scene, 45_000) == %TransitionPolicy{
             duration_ms: 45_000,
             scaling: :none
           }
  end

  test "scene persistence accepts a ten-minute custom activation transition" do
    room = Repo.insert!(%Room{name: "Transition Policy Room"})

    assert {:ok, scene} =
             Scenes.create_scene(%{
               name: "Slow Evening",
               room_id: room.id,
               activation_transition_ms: 600_000
             })

    assert Repo.get!(Scene, scene.id).activation_transition_ms == 600_000

    assert {:error, changeset} = Scenes.update_scene(scene, %{activation_transition_ms: 0})
    assert Keyword.has_key?(changeset.errors, :activation_transition_ms)
  end
end
