defmodule Hueworks.UtilTest do
  use ExUnit.Case, async: true

  alias Hueworks.Util

  test "clamp accepts numeric strings" do
    assert Util.clamp("51", 1, 100) == 51
    assert Util.clamp("0", 1, 100) == 1
    assert Util.clamp("150", 1, 100) == 100
  end
end
