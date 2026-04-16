defmodule Hueworks.AppEnvRestoreTest do
  use Hueworks.DataCase, async: false

  @env_key :codex_app_env_restore_test_key

  setup do
    original = Application.get_env(:hueworks, @env_key)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:hueworks, @env_key)
      else
        Application.put_env(:hueworks, @env_key, original)
      end
    end)

    :ok
  end

  test "restore_app_env deletes nil-backed keys so defaults work again" do
    Application.put_env(:hueworks, @env_key, :temporary)

    restore_app_env(:hueworks, @env_key, nil)

    assert Application.get_env(:hueworks, @env_key, :default_value) == :default_value
  end

  test "restore_app_env puts back original values when one existed" do
    Application.put_env(:hueworks, @env_key, :temporary)

    restore_app_env(:hueworks, @env_key, :original_value)

    assert Application.get_env(:hueworks, @env_key) == :original_value
  end
end
