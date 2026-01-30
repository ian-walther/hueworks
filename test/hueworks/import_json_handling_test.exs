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

  defp temp_file(name, contents) do
    base = System.tmp_dir!()
    path = Path.join(base, "hueworks_#{name}")
    File.write!(path, contents)

    on_exit(fn ->
      if File.exists?(path), do: File.rm!(path)
    end)

    path
  end
end
