defmodule Hueworks.UtilTest do
  use ExUnit.Case, async: true

  alias Hueworks.Util

  test "clamp accepts numeric strings" do
    assert Util.clamp("51", 1, 100) == 51
    assert Util.clamp("0", 1, 100) == 1
    assert Util.clamp("150", 1, 100) == 100
  end

  test "display_name falls back to name" do
    assert Util.display_name(%{display_name: "Fancy", name: "Lamp"}) == "Fancy"
    assert Util.display_name(%{display_name: nil, name: "Lamp"}) == "Lamp"
    assert Util.display_name(%{name: "Lamp"}) == "Lamp"
    assert Util.display_name(%{}) == "Unknown"
  end
end
