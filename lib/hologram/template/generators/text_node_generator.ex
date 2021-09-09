defmodule Hologram.Template.TextNodeGenerator do
  def generate(content) do
    content =
      content
      |> String.replace("\n", "\\n")
      |> String.replace("'", "\\'")
      |> String.replace("&lcub;", "{")
      |> String.replace("&rcub;", "}")

    "{ type: 'text', content: '#{content}' }"
  end
end
