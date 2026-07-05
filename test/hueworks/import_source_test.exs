defmodule Hueworks.ImportSourceTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Source

  test "normalizes known source atoms and strings" do
    for source <- [:hue, :ha, :caseta, :z2m] do
      assert Source.normalize(source) == source
      assert Source.normalize(to_string(source)) == source
      assert Source.parse(source) == {:ok, source}
      assert Source.parse(to_string(source)) == {:ok, source}
    end
  end

  test "rejects unknown source values without creating atoms" do
    assert Source.normalize("surprise") == nil
    assert Source.normalize(:surprise) == nil
    assert Source.normalize(nil) == nil
    assert Source.parse("surprise") == {:error, "Unsupported bridge type: surprise"}
    assert Source.parse(nil) == {:error, "Missing bridge type"}
  end
end
