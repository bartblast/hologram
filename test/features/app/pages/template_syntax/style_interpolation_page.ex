defmodule HologramFeatureTests.TemplateSyntax.StyleInterpolationPage do
  use Hologram.Page

  route "/template-syntax/style-interpolation"

  layout HologramFeatureTests.Components.DefaultLayout

  # A closing style tag, an ampersand, both kinds of quote, a backslash and a child combinator:
  # everything the escaping has to carry through intact, and the one sequence it must not let end
  # the element. The rule the closing tag carries would hide the div if it ever took effect.
  #
  # No newline in the value on purpose - Chrome serializes one inside a computed "content" as
  # "\a ", which the test's unescape would mangle. The newline case is covered by the renderer
  # unit tests on both sides.
  def init(_params, component, _server) do
    put_state(
      component,
      :value,
      ~s(</style><style>#style_interpolation { visibility: hidden }</style> & "a" 'b' \\c > d)
    )
  end

  # The script reads the stylesheet's effect and repeats the value through a script interpolation,
  # which #1101 established arrives exact. The test compares the two, so nothing is written twice.
  def template do
    ~HOLO"""
    <div id="style_interpolation">abc</div>
    <style id="style_interpolation_sheet">
      #style_interpolation::after \{ content: "{@value}" \}
    </style>
    <script>
      window.__styleInterpolationExpected = "{@value}";
      window.__styleInterpolation = \{
        content: getComputedStyle(document.querySelector("#style_interpolation"), "::after").content,
        visibility: getComputedStyle(document.querySelector("#style_interpolation")).visibility,
        text: document.getElementById("style_interpolation_sheet").textContent
      \};
    </script>
    """
  end
end
