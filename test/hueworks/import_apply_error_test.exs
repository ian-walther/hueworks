defmodule Hueworks.Import.ApplyErrorTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.ApplyError

  test "translates known stale-review failures and hides raw tuples from primary copy" do
    assert ApplyError.message({:duplicate_classification_changed, :light, "light.one"}) ==
             "Duplicate classification changed for light light.one. Refresh the review and check the choices again."

    assert ApplyError.message({:invalid_duplicate, :group, "group.one"}) ==
             "The duplicate choice for group group.one is no longer valid. Refresh the review and choose again."

    assert ApplyError.message({:stale_resolution, :light, "light.two"}) ==
             "The review is out of date for light light.two. Refresh it and check the choices again."
  end

  test "uses generic primary copy with bounded diagnostic detail for unknown failures" do
    message = ApplyError.message({:transaction_failed, String.duplicate("detail", 100)})

    assert message =~ "Import could not be applied."
    assert String.length(message) < 300
  end
end
