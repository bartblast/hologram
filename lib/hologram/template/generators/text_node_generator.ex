defmodule Hologram.Template.TextNodeGenerator do
  def generate(content) do
    opts = [global: true]

    content =
      content
      |> String.replace("\n", "\\n", opts)
      |> String.replace("'", "\\'", opts)
      |> String.replace("&lcub;", "{", opts)
      |> String.replace("&rcub;", "}", opts)

    "{ type: 'text', content: '#{content}' }"
  end
end
