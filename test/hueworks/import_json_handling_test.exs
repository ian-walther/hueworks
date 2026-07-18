defmodule Hueworks.Import.JsonHandlingTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureIO

  test "normalize task logs error on invalid JSON" do
    path = temp_file("invalid-normalize.json", "{invalid-json")

    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.NormalizeBridgeImports.run([path])
      end)

    assert output =~ "Failed to normalize"
  end

  test "materialize task logs error on invalid JSON" do
    path = temp_file("invalid-materialize.json", "not-json")

    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.MaterializeBridgeImports.run([path])
      end)

    assert output =~ "Failed to materialize"
  end

  test "normalize task rejects unsupported bridge type without creating atoms" do
    source = "unsupported_normalize_#{System.unique_integer([:positive])}"

    path =
      temp_json_file("unsupported-normalize.json", %{
        "bridge" => %{"id" => 1, "type" => source, "name" => "Bad", "host" => "bad.local"},
        "raw" => %{},
        "fetched_at" => "2026-01-01T00:00:00Z"
      })

    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.NormalizeBridgeImports.run([path])
      end)

    assert output =~ "Unsupported bridge type: #{source}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(source) end
  end

  test "materialize task prints missing bridge errors" do
    path =
      temp_json_file("missing-bridge-materialize.json", %{
        "bridge" => %{"host" => "missing.local", "type" => "hue"},
        "normalized" => %{"areas" => [], "lights" => [], "groups" => [], "memberships" => %{}}
      })

    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.MaterializeBridgeImports.run([path])
      end)

    assert output =~ "No bridge found for missing.local (hue)"
  end

  test "materialize task rejects unsupported bridge type without creating atoms" do
    source = "unsupported_materialize_#{System.unique_integer([:positive])}"

    path =
      temp_json_file("unsupported-materialize.json", %{
        "bridge" => %{"host" => "missing.local", "type" => source},
        "normalized" => %{"areas" => [], "lights" => [], "groups" => [], "memberships" => %{}}
      })

    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.MaterializeBridgeImports.run([path])
      end)

    assert output =~ "Unsupported bridge type: #{source}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(source) end
  end

  defp temp_file(name, contents) do
    base = System.tmp_dir!()
    path = Path.join(base, "hueworks_#{name}")
    File.write!(path, contents)

    on_exit(fn ->
      if File.exists?(path), do: File.rm!(path)
    end)

    path
  end

  defp temp_json_file(name, payload) do
    temp_file(name, Jason.encode!(payload))
  end
end
