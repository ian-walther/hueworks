defmodule Hueworks.Subscription.HueEventStream.ParserTest do
  use ExUnit.Case, async: true

  alias Hueworks.Subscription.HueEventStream.Parser

  test "consume buffers partial payloads until an event boundary arrives" do
    event = %{"data" => [%{"type" => "light", "id_v1" => "/lights/11"}]}
    payload = "data: " <> Jason.encode!(event) <> "\n\n"
    split_at = div(byte_size(payload), 2)
    {chunk_1, chunk_2} = :erlang.split_binary(payload, split_at)

    assert {[], rest} = Parser.consume("", chunk_1)
    assert rest != ""

    assert {[%{"type" => "light", "id_v1" => "/lights/11"}], ""} = Parser.consume(rest, chunk_2)
  end

  test "consume unwraps envelope lists and ignores invalid payloads" do
    first =
      "data: " <>
        Jason.encode!(%{"data" => [%{"type" => "light", "id_v1" => "/lights/1"}]}) <> "\n\n"

    second = "data: " <> Jason.encode!(%{"type" => "grouped_light", "id_v1" => "/groups/2"}) <> "\n\n"
    invalid = "data: {not-json}\n\n"

    assert {events, ""} = Parser.consume("", first <> second <> invalid)

    assert events == [
             %{"type" => "light", "id_v1" => "/lights/1"},
             %{"type" => "grouped_light", "id_v1" => "/groups/2"}
           ]
  end
end
