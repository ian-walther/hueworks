defmodule Hueworks.CredentialsTest do
  use ExUnit.Case, async: false

  alias Hueworks.Credentials

  setup do
    original = Application.get_env(:hueworks, :credentials_root)

    on_exit(fn ->
      Application.put_env(:hueworks, :credentials_root, original)
    end)

    :ok
  end

  test "defaults to priv/credentials under the project root" do
    Application.delete_env(:hueworks, :credentials_root)

    assert String.ends_with?(Credentials.root_path(), "/priv/credentials")
    assert Credentials.caseta_dir() == Path.join(Credentials.root_path(), "caseta")

    assert Credentials.caseta_staging_dir() ==
             Path.join(Credentials.caseta_dir(), "staging")
  end

  test "uses configured credentials root for caseta storage paths" do
    Application.put_env(:hueworks, :credentials_root, "/credentials")

    assert Credentials.root_path() == "/credentials"
    assert Credentials.caseta_dir() == "/credentials/caseta"
    assert Credentials.caseta_staging_dir() == "/credentials/caseta/staging"
  end
end
