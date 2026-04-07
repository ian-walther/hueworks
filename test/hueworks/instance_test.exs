defmodule Hueworks.InstanceTest do
  use ExUnit.Case, async: true

  alias Hueworks.Instance

  test "z2m client ids include the configured instance slug" do
    assert Instance.z2m_client_id("hwz2ms", 7) == "hwz2ms7-test"
    assert Instance.z2m_client_id("hwz2mc", 12) == "hwz2mc12-test"
  end

  test "environment override wins and is normalized" do
    previous = System.get_env("HUEWORKS_INSTANCE_NAME")

    try do
      System.put_env("HUEWORKS_INSTANCE_NAME", "Ian Local Dev!")

      assert Instance.slug() == "ian-local-de"
      assert Instance.z2m_client_id("hwz2ms", 3) == "hwz2ms3-ian-local-de"
    after
      if previous do
        System.put_env("HUEWORKS_INSTANCE_NAME", previous)
      else
        System.delete_env("HUEWORKS_INSTANCE_NAME")
      end
    end
  end
end
