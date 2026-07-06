defmodule Hueworks.Scenes.PowerPolicy do
  @moduledoc false

  @values [:default_on, :default_off, :force_on, :force_off, :follow_presence]

  def values, do: @values

  def parse(value) when value in [nil, true, "true", 1, "1", :on, "on"], do: :default_on
  def parse(value) when value in [false, "false", 0, "0", :off, "off"], do: :default_off
  def parse(value) when value in [:default_on, "default_on"], do: :default_on
  def parse(value) when value in [:default_off, "default_off"], do: :default_off
  def parse(value) when value in [:force_on, "force_on"], do: :force_on
  def parse(value) when value in [:force_off, "force_off"], do: :force_off
  def parse(value) when value in [:follow_presence, "follow_presence"], do: :follow_presence
  def parse(_value), do: :default_on

  def resolve(policy, presence_input) do
    case parse(policy) do
      :default_on -> :on
      :default_off -> :off
      :force_on -> :on
      :force_off -> :off
      :follow_presence -> presence_power(presence_input)
    end
  end

  def overridable?(policy), do: parse(policy) in [:default_on, :default_off]

  def label(:default_on), do: "Default On"
  def label(:default_off), do: "Default Off"
  def label(:force_on), do: "Force On"
  def label(:force_off), do: "Force Off"
  def label(:follow_presence), do: "Follow Presence"
  def label(:mixed), do: "..."

  def cycle(:default_on), do: :default_off
  def cycle(:default_off), do: :force_on
  def cycle(:force_on), do: :force_off
  def cycle(:force_off), do: :default_on
  def cycle(_policy), do: :default_on

  defp presence_power(%{occupied: true}), do: :on
  defp presence_power(_presence_input), do: :off
end
