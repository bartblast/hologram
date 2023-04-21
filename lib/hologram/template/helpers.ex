defmodule Hologram.Template.Helpers do
  @doc """
  Determines whether the given tag is an element or a component.

  ## Examples

      iex> tag_type("div")
      :element

      iex> tag_type("MyComponent")
      :component
  """
  @spec tag_type(String.t()) :: :component | :element
  def tag_type(<<first_char::binary-size(1), _rest>>) do
    if String.downcase(first_char) == first_char do
      :element
    else
      :component
    end
  end
end
