defmodule Hologram.Template.TextNodeGenerator do
  def generate(text) do
    text =
      String.replace(text, "\n", "\\n", global: true)
      |> String.replace("'", "\\'", global: true)

    "{ type: 'text_node', text: '#{text}' }"
  end
end
