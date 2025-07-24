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
    tag_name in @void_html_elements || tag_name == "slot"
  end
end
