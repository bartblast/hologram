defmodule Hologram.Template.HelpersTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Helpers

  # Kept as a separate copy of the list in lib, on purpose: a test that looped the module's own map
  # would pass no matter how an entry was spelled there.
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

  describe "normalize_tag_name/1" do
    test "HTML tag name with uppercase chars" do
      assert normalize_tag_name("DIV") == "div"
      assert normalize_tag_name("DiV") == "div"
    end

    test "HTML tag name that is already lowercase" do
      assert normalize_tag_name("div") == "div"
    end

    test "SVG tag name that lost its case" do
      assert normalize_tag_name("lineargradient") == "linearGradient"
      assert normalize_tag_name("LINEARGRADIENT") == "linearGradient"
    end

    test "SVG tag name that is already spelled the way the parser spells it" do
      assert normalize_tag_name("linearGradient") == "linearGradient"
    end

    test "SVG tag name the parser has no spelling for" do
      # The list belongs to the HTML parsing spec and predates feDropShadow, so no markup produces
      # that element. The name is treated like any other name the parser does not restore.
      assert normalize_tag_name("feDropShadow") == "fedropshadow"
    end

    test "every SVG tag name whose case the parser restores" do
      for {lowercased, restored} <- @svg_adjusted_tag_names do
        assert normalize_tag_name(lowercased) == restored
        assert normalize_tag_name(restored) == restored
      end
    end
  end

  describe "tag_type/1" do
    test "element" do
      assert tag_type("div") == :element
    end

    test "component" do
      assert tag_type("MyComponent") == :component
    end
  end

  describe "void_element?/1" do
    test "void HTML element" do
      assert void_element?("br")
    end

    test "non-void HTML element" do
      refute void_element?("div")
    end

    test "slot element" do
      assert void_element?("slot")
    end

    test "SVG element that can be self-closed" do
      refute void_element?("path")
    end

    test "window element" do
      assert void_element?("window")
    end

    test "document element" do
      assert void_element?("document")
    end
  end
end
