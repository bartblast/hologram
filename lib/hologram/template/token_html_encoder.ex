# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenHTMLEncoder do
  def encode(tokens) when is_list(tokens) do
    Enum.map(tokens, &encode/1)
    |> Enum.join("")
  end

  def encode({:start_tag, {tag, attrs}}) do
    attrs =
      Enum.map(attrs, fn {key, value} ->
        if value do
          key <> "=\"" <> value <> "\""
        else
          key <> "=\"\""
        end
      end)

    "<#{tag} #{attrs}>"
  end

  def encode({:end_tag, tag}), do: "</#{tag}>"

  def encode({:text, str}), do: str

  def encode({:symbol, :"\""}), do: "~Hologram.Template.TokenCombiner[:double_quote]"

  def encode({:symbol, symbol}), do: to_string(symbol)

  def encode({:string, str}), do: str

  def encode({:whitespace, char}), do: char

  def encode(nil), do: ""
end
