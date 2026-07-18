defmodule Hueworks.OnboardingTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Onboarding
  alias Hueworks.Repo
  alias Hueworks.Schemas.{AppSetting, Area, Bridge, Light, Scene}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    :ok
  end

  test "an untouched installation is eligible for first-run setup" do
    status = Onboarding.status()

    assert status.path == nil
    assert status.empty?
    assert status.auto_open?
    refute status.finished?
    refute status.dismissed?
  end

  test "selected path, completion, and dismissal are the only persisted onboarding state" do
    assert {:ok, selected} = Onboarding.choose_path(:ha_assisted)
    assert selected.onboarding_path == "ha_assisted"

    assert %{path: :ha_assisted, auto_open?: true} = Onboarding.status()

    assert {:ok, finished} = Onboarding.finish()
    assert %DateTime{} = finished.onboarding_completed_at
    assert finished.onboarding_dismissed_at == nil
    assert %{finished?: true, dismissed?: false} = Onboarding.status()

    assert {:ok, dismissed} = Onboarding.dismiss()
    assert dismissed.onboarding_completed_at == nil
    assert %DateTime{} = dismissed.onboarding_dismissed_at
    assert %{finished?: false, dismissed?: true} = Onboarding.status()
  end

  test "progress is derived from committed configuration after cache loss" do
    {:ok, _settings} =
      Hueworks.AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.006,
        timezone: "America/New_York"
      })

    bridge =
      Repo.insert!(%Bridge{
        type: :hue,
        name: "Hue Bridge",
        host: "192.0.2.10",
        credentials: %Bridge.Credentials{api_key: "test-key"},
        import_complete: true
      })

    area = Repo.insert!(%Area{name: "Living Area"})

    Repo.insert!(%Light{
      name: "Lamp",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      area_id: area.id
    })

    Repo.insert!(%Scene{name: "Auto", area_id: area.id})
    HueworksApp.Cache.flush_namespace(:app_settings)

    status = Onboarding.status()

    assert status.location_configured?
    assert status.bridge_count == 1
    assert status.pending_import_count == 0
    assert status.area_count == 1
    assert status.scene_count == 1
    refute status.empty?
    refute status.auto_open?
  end

  test "only supported setup paths are accepted" do
    assert {:error, :invalid_path} = Onboarding.choose_path(:something_else)
    assert Onboarding.status().path == nil
  end
end
