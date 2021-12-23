# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenHTMLEncoder do
  def encode(arg, escape \\ true)

  def encode(tokens, escape) when is_list(tokens) do
    Enum.map(tokens, &(encode(&1, escape)))
    |> Enum.join("")
  end

  def encode({:start_tag, {tag, attrs}}, _) do
    attrs =
      Enum.map(attrs, fn {key, value} ->
        if value do
          key <> "=\"" <> value <> "\""
        else
          # DEFER: implement boolean attributes, see: https://github.com/segmetric/hologram/issues/15
          key <> "=\"\""
        end
      end)

    "<#{tag} #{attrs}>"
  end

  def encode({:end_tag, tag}, _), do: "</#{tag}>"

  def encode({:text_tag, str}, _), do: str

  def encode({:symbol, :"\""}, true), do: "~Hologram.Template.TokenCombiner[:double_quote]"

  def encode({:symbol, symbol}, _), do: to_string(symbol)

  def encode({:string, str}, _), do: str

  def encode({:whitespace, char}, _), do: char

  def encode(nil, _), do: ""
end
