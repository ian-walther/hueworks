defmodule Hueworks.CleanSetupContractTest do
  use ExUnit.Case, async: true

  test "ecto.reset creates an empty migrated database without bridge seeds" do
    aliases = Mix.Project.config() |> Keyword.fetch!(:aliases)

    assert aliases[:"ecto.reset"] == ["ecto.drop", "ecto.setup"]
  end

  test "the primary Compose path does not require secrets.json" do
    compose = File.read!("docker-compose.yml")

    refute compose =~ "secrets.json"
    refute compose =~ "BRIDGE_SECRETS_PATH"
  end

  test "the optional Compose overlay owns file-based bridge seeding" do
    compose = File.read!("docker-compose.seeds.yml")

    assert compose =~ "BRIDGE_SECRETS_PATH: /run/hueworks/secrets.json"
    assert compose =~ "./secrets.json:/run/hueworks/secrets.json:ro"
  end
end
