defmodule HueworksWeb.ThemeCssTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @stylesheet Path.join(@root, "assets/css/app.css")
  @theme_marker "/* Component styles: color literals below this marker are prohibited. */"
  @literal_color ~r/#[0-9a-f]{3,8}\b|rgba?\(\s*\d|hsla?\(\s*\d|(?<![-\w])(?:white|black)(?![-\w])/i

  test "all literal CSS colors live in the centralized theme block" do
    css = File.read!(@stylesheet)

    assert [theme, components] = String.split(css, @theme_marker, parts: 2)
    assert theme =~ "--ink: light-dark("
    assert theme =~ "--hw-hue-spectrum:"

    refute Regex.match?(@literal_color, components),
           "component CSS contains a hardcoded color outside the theme block"
  end

  test "power buttons preserve the warm-on and cool-off visual language" do
    css = File.read!(@stylesheet)

    assert css =~ "--hw-power-on: var(--accent-2);"
    assert css =~ "--hw-power-off: var(--accent);"

    assert css =~
             ~r/\.hw-button-on\s*\{[^}]*background:[^;]*var\(--hw-power-on\)/s

    assert css =~
             ~r/\.hw-button-off\s*\{[^}]*background:[^;]*var\(--hw-power-off\)/s
  end

  test "initial import area markup has matching component styles" do
    css = File.read!(@stylesheet)

    for selector <- ~w(
      .hw-import-area-list
      .hw-import-area-card
      .hw-import-area-header
      .hw-import-area-actions
    ) do
      assert css =~ selector, "missing initial import style for #{selector}"
    end

    refute css =~ ".hw-import-room-"
  end

  describe "field flow layout" do
    test "notes take their own row and field groups stay content-sized on wide screens" do
      css = File.read!(@stylesheet)

      assert css =~ ~r/\.hw-field-flow-note\s*\{[^}]*flex: 1 1 100%;[^}]*min-width: 0;/s
      assert css =~ ~r/\.hw-field-group\s*\{[^}]*flex: 0 0 auto;/s
    end

    test "mini-labels sit above paired inputs so each input keeps its full column" do
      css = File.read!(@stylesheet)

      assert css =~
               ~r/\.hw-field-pair > \.hw-field-compact,\s*\.hw-field-triplet > \.hw-field-compact\s*\{[^}]*flex-direction: column;/s

      refute media_rules(css, "(max-width: 520px)") =~ ".hw-mini-label"
    end

    test "single-column sections do not grow to fit their content" do
      css = File.read!(@stylesheet)

      assert css =~ ~r/\.hw-circadian-sections\s*\{[^}]*grid-template-columns: minmax\(0, 1fr\);/s
    end

    test "field groups and card fields fill the screen at the narrow breakpoint" do
      rules = media_rules(File.read!(@stylesheet), "(max-width: 720px)")

      assert rules =~
               ~r/\.hw-field-flow \.hw-field-group\s*\{[^}]*flex: 1 1 100%;[^}]*min-width: 0;/s

      assert rules =~ ~r/\.hw-field-flow-card \.hw-field-compact,?[^{]*\{[^}]*width: 100%;/s
      assert rules =~ ~r/\.hw-compact-input,\s*\.hw-compact-select\s*\{[^}]*min-width: 0;/s
    end

    test "pairs and triplets stack at the narrowest breakpoint, including inside cards" do
      rules = media_rules(File.read!(@stylesheet), "(max-width: 520px)")

      for selector <- ~w(.hw-field-pair .hw-field-triplet) do
        assert rules =~ selector
        assert rules =~ ".hw-field-flow-card #{selector}"
      end

      assert rules =~
               ~r/\.hw-field-flow-card \.hw-field-triplet\s*\{[^}]*grid-template-columns: minmax\(0, 1fr\);/s
    end

    test "the field flow never hides overflow to look like it fits" do
      css = File.read!(@stylesheet)

      for selector <-
            ~w(.hw-field-flow .hw-field-flow-row .hw-field-flow-note .hw-field-group .hw-field-pair .hw-field-triplet .hw-field-compact) do
        refute css =~ ~r/#{Regex.escape(selector)}\s*\{[^}]*overflow/s,
               "#{selector} clips its content"
      end
    end
  end

  defp media_rules(css, query) do
    css
    |> String.split("@media #{query} {")
    |> tl()
    |> Enum.map_join("\n", &until_block_closes(&1, 1, []))
  end

  defp until_block_closes(<<"{", rest::binary>>, depth, acc),
    do: until_block_closes(rest, depth + 1, ["{" | acc])

  defp until_block_closes(<<"}", _rest::binary>>, 1, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp until_block_closes(<<"}", rest::binary>>, depth, acc),
    do: until_block_closes(rest, depth - 1, ["}" | acc])

  defp until_block_closes(<<char::utf8, rest::binary>>, depth, acc),
    do: until_block_closes(rest, depth, [<<char::utf8>> | acc])

  test "web templates and presentation modules do not construct literal CSS colors" do
    files =
      Path.wildcard(Path.join(@root, "lib/hueworks_web/**/*.{ex,heex}")) ++
        Path.wildcard(Path.join(@root, "assets/js/**/*.js"))

    violations =
      Enum.filter(files, fn file ->
        Regex.match?(@literal_color, File.read!(file))
      end)

    assert violations == [],
           "hardcoded UI colors found outside CSS theme tokens: #{inspect(violations)}"
  end
end
