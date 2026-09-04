defmodule HueworksWeb.CssClassesTest do
  @moduledoc """
  Keeps `assets/css/app.css` and the templates honest with each other.

  Every `hw-*` class the stylesheet defines must be used by a template, and
  every `hw-*` class a template uses must be defined by the stylesheet. A
  handful of scope hooks carry no styling on purpose and are listed below.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @stylesheet Path.join(@root, "assets/css/app.css")

  # Classes that exist to scope or identify markup, never to style it.
  @unstyled_hooks ~w(
    hw-page
    hw-control-page
    hw-areas-page
    hw-lights-page
    hw-scene-editor-page
    hw-setup-page
    hw-config-page
    hw-config-content-frame
    hw-app-flash-error
    hw-app-flash-info
  )

  test "every class the stylesheet defines is used by a template" do
    unused = defined_classes() -- used_classes()

    assert unused == [],
           "app.css defines classes no template uses:\n  " <> Enum.join(unused, "\n  ")
  end

  test "every class a template uses is defined by the stylesheet" do
    defined = defined_classes()
    {prefixes, names} = Enum.split_with(used_tokens(), &String.ends_with?(&1, "-"))

    undefined =
      ((names -- defined) -- @unstyled_hooks) ++
        Enum.reject(prefixes, fn prefix -> Enum.any?(defined, &String.starts_with?(&1, prefix)) end)

    assert undefined == [],
           "templates use classes app.css never defines:\n  " <> Enum.join(undefined, "\n  ")
  end

  defp defined_classes do
    @stylesheet
    |> File.read!()
    |> String.replace(~r{/\*.*?\*/}s, "")
    |> then(&Regex.scan(~r/\.(hw-[a-z0-9-]+)/, &1, capture: :all_but_first))
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp used_classes do
    used_tokens()
    |> Enum.flat_map(fn token ->
      if String.ends_with?(token, "-") do
        Enum.filter(defined_classes(), &String.starts_with?(&1, token))
      else
        [token]
      end
    end)
    |> Enum.uniq()
  end

  # `hw-foo-#{...}` interpolations surface as the prefix `hw-foo-`; custom
  # properties (`--hw-foo`) are excluded by the lookbehind.
  defp used_tokens do
    Path.wildcard(Path.join(@root, "lib/hueworks_web/**/*.{ex,heex}"))
    |> Enum.flat_map(fn file ->
      Regex.scan(~r/(?<![-\w])hw-[a-z0-9-]+/, File.read!(file))
    end)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
