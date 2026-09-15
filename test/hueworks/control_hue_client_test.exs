defmodule Hueworks.Control.HueClientTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.HueClient

  # The Hue v1 API answers HTTP 200 even when it refuses a command; refusals are error
  # objects inside the body. See docs/hue-command-pacing.md.

  test "a body of successes is a success" do
    body = ~s([{"success":{"/lights/1/state/bri":120}},{"success":{"/lights/1/state/on":true}}])
    assert HueClient.interpret_body(body) == {:ok, :ok}
  end

  test "an internal error is a retryable busy signal" do
    body =
      ~s([{"success":{"/groups/1/action/on":true}},{"error":{"type":901,"address":"/groups/1/action/bri","description":"Internal error, 503"}}])

    assert {:error, {:hue_busy, [%{"type" => 901}]}} = HueClient.interpret_body(body)
  end

  test "a parameter refusal is a permanent rejection" do
    body =
      ~s([{"error":{"type":201,"address":"/lights/1/state/bri","description":"parameter, bri, is not modifiable. Device is set to off."}}])

    assert {:error, {:hue_rejected, [%{"type" => 201}]}} = HueClient.interpret_body(body)
  end

  test "a body that is not a Hue result list is accepted as before" do
    assert HueClient.interpret_body("") == {:ok, :ok}
    assert HueClient.interpret_body(~s({"ok":true})) == {:ok, :ok}
  end
end
