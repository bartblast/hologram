# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenHTMLEncoder do
  @escaped_double_quote "~Hologram.Template.Parser[:double_quote]"

  def encode(arg)

  def encode(tokens) when is_list(tokens) do
    Enum.map(tokens, &encode/1)
    |> Enum.join("")
  end

  def encode({:start_tag, {tag, attrs}}) do
    attrs =
      Enum.map(attrs, fn {key, value} ->
        if value do
          value = String.replace(value, "\"", @escaped_double_quote)
          key <> "=\"" <> value <> "\""
        else
          # DEFER: implement boolean attributes, see: https://github.com/segmetric/hologram/issues/15
          key <> "=\"\""
        end
      end)

    "<#{tag} #{attrs}>"
  end

  def encode({:end_tag, tag}), do: "</#{tag}>"

  def encode({:text_tag, str}), do: str

  def encode({:symbol, symbol}), do: to_string(symbol)

  def encode({:string, str}), do: str

  def encode({:whitespace, char}), do: char

  def encode(nil), do: ""

  def escaped_double_quote, do: @escaped_double_quote
end
