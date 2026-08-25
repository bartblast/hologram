defmodule Hologram.Template.Helpers do
  @moduledoc false

  # See: https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_html_elements [
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr"
  ]

  # The tag names whose case the HTML parser restores inside <svg>. Everywhere else a tag name has
  # no case at all: the tokenizer lowercases it before anything else sees it, and only these names
  # are given their spelling back.
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#adjust-svg-tag-name
  @svg_adjusted_tag_names %{
    "altglyph" => "altGlyph",
    "altglyphdef" => "altGlyphDef",
    "altglyphitem" => "altGlyphItem",
    "animatecolor" => "animateColor",
    "animatemotion" => "animateMotion",
    "animatetransform" => "animateTransform",
    "clippath" => "clipPath",
    "feblend" => "feBlend",
    "fecolormatrix" => "feColorMatrix",
    "fecomponenttransfer" => "feComponentTransfer",
    "fecomposite" => "feComposite",
    "feconvolvematrix" => "feConvolveMatrix",
    "fediffuselighting" => "feDiffuseLighting",
    "fedisplacementmap" => "feDisplacementMap",
    "fedistantlight" => "feDistantLight",
    "feflood" => "feFlood",
    "fefunca" => "feFuncA",
    "fefuncb" => "feFuncB",
    "fefuncg" => "feFuncG",
    "fefuncr" => "feFuncR",
    "fegaussianblur" => "feGaussianBlur",
    "feimage" => "feImage",
    "femerge" => "feMerge",
    "femergenode" => "feMergeNode",
    "femorphology" => "feMorphology",
    "feoffset" => "feOffset",
    "fepointlight" => "fePointLight",
    "fespecularlighting" => "feSpecularLighting",
    "fespotlight" => "feSpotLight",
    "fetile" => "feTile",
    "feturbulence" => "feTurbulence",
    "foreignobject" => "foreignObject",
    "glyphref" => "glyphRef",
    "lineargradient" => "linearGradient",
    "radialgradient" => "radialGradient",
    "textpath" => "textPath"
  }

  @doc """
  Spells a tag name the way the HTML parser would.

  ## Examples

      iex> normalize_tag_name("DIV")
      "div"

      iex> normalize_tag_name("lineargradient")
      "linearGradient"
  """
  @spec normalize_tag_name(String.t()) :: String.t()
  def normalize_tag_name(tag_name) do
    downcased = String.downcase(tag_name)

    Map.get(@svg_adjusted_tag_names, downcased, downcased)
  end

  @doc """
  Determines whether the given tag is an element or a component.

  ## Examples

      iex> tag_type("div")
      :element

      iex> tag_type("MyComponent")
      :component
  """
  @spec tag_type(String.t()) :: :component | :element
  def tag_type(<<first_char::binary-size(1), _rest::binary>>) do
    if String.downcase(first_char) == first_char do
      :element
    else
      :component
    end
  end

  @doc """
  Determines whether the given tag name belongs to a void element.

  ## Examples

      iex> void_element?("br")
      true

      iex> void_element?("div")
      false
  """
  @spec void_element?(String.t()) :: boolean
  def void_element?(tag_name) do
    tag_name in @void_html_elements || tag_name in ["slot", "window", "document"]
  end
end
