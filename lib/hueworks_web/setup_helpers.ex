defmodule HueworksWeb.SetupHelpers do
  @moduledoc false

  def count_label(count, singular) when is_integer(count) do
    label =
      case {count, singular} do
        {1, value} ->
          value

        {_, value} when value in ["entity", "relevant entity", "HA-only entity"] ->
          String.replace_suffix(value, "entity", "entities")

        {_, value} ->
          value <> "s"
      end

    "#{count} #{label}"
  end

  def operation_error(%Ecto.Changeset{}), do: "the requested values were not valid"
  def operation_error(reason) when is_binary(reason), do: reason

  def operation_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  def operation_error(_reason), do: "unexpected error"
end
