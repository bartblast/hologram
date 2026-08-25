defmodule HologramFeatureTests.TemplateSyntax.InlineStylesheetPage do
  use Hologram.Page

  route "/template-syntax/inline-stylesheet"

  layout HologramFeatureTests.Components.DefaultLayout

  # A child combinator and an ampersand: the characters an entity encoder rewrites and a CSS
  # parser does not decode back. The script runs while the document is still parsing, before the
  # runtime boots, so what it records is the stylesheet the server wrote rather than the client's
  # render of it.
  def template do
    ~HOLO"""
    <div id="inline_stylesheet"><span>abc</span></div>
    <style id="inline_stylesheet_sheet">
      #inline_stylesheet > span \{ color: rgb(1, 2, 3) \}
      #inline_stylesheet::after \{ content: "a & b" \}
    </style>
    <script>
      window.__inlineStylesheet = \{
        color: getComputedStyle(document.querySelector("#inline_stylesheet span")).color,
        content: getComputedStyle(document.querySelector("#inline_stylesheet"), "::after").content,
        text: document.getElementById("inline_stylesheet_sheet").textContent
      \};
    </script>
    """
  end
end
