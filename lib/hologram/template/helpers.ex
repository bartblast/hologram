defmodule Hologram.Template.Helpers do
  def tag_type(tag_name) do
    first_char = String.at(tag_name, 0)
    downcased_first_char = String.downcase(first_char)

    if first_char == downcased_first_char do
      :element
    else
      :component
    end
  end
end
