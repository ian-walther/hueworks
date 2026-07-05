defmodule Hueworks.Import.NormalizeJsonTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.NormalizeJson

  test "normalizes atoms to JSON-safe strings" do
    input = %{
      source: :hue,
      metadata: %{"baz" => :qux, foo: :bar},
      list: [:one, %{:two => 2}, ["three", :four]]
    }

    assert NormalizeJson.to_map(input) == %{
             "source" => "hue",
             "metadata" => %{"foo" => "bar", "baz" => "qux"},
             "list" => ["one", %{"two" => 2}, ["three", "four"]]
           }
  end

  test "preserves JSON boolean and nil values" do
    input = %{
      capabilities: %{
        brightness: true,
        color: false,
        color_temp: nil
      },
      members: [nil, true, false]
    }

    assert NormalizeJson.to_map(input) == %{
             "capabilities" => %{
               "brightness" => true,
               "color" => false,
               "color_temp" => nil
             },
             "members" => [nil, true, false]
           }
  end
end
