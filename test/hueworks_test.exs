defmodule HueworksTest do
  use ExUnit.Case
  doctest Hueworks

  test "greets the world" do
    assert Hueworks.hello() == :world
  end
end
