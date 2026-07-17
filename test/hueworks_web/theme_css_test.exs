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
