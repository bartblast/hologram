defmodule Hologram.Template.TextNodeGenerator do
  def generate(content) do
    content =
      String.replace(content, "\n", "\\n", global: true)
      |> String.replace("'", "\\'", global: true)

    "{ type: 'text', content: '#{content}' }"
  end
end
