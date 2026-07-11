defmodule Hueworks.RuntimeConfigTest do
  use ExUnit.Case, async: false

  test "production endpoint URL uses the configured public scheme" do
    env = %{
      "DATABASE_PATH" => "/tmp/hueworks-runtime-config-test.db",
      "SECRET_KEY_BASE" => "a_secure_runtime_config_test_value",
      "PHX_HOST" => "hueworks.home",
      "PHX_SCHEME" => "http"
    }

    previous = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)
    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    config = Config.Reader.read!("config/runtime.exs", env: :prod)
    endpoint_config = get_in(config, [:hueworks, HueworksWeb.Endpoint])

    assert endpoint_config[:url] == [host: "hueworks.home", port: 4000, scheme: "http"]
  end
end
