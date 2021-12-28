# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenHTMLEncoder do
  def encode(arg)

  def encode(tokens) when is_list(tokens) do
    Enum.map(tokens, &encode/1)
    |> Enum.join("")
  end

  def encode({:start_tag, {tag_name, attrs}}) do
    attrs =
      Enum.map(attrs, fn {type, key, value} ->
        case type do
          :boolean ->
            # DEFER: implement boolean attributes, see: https://github.com/segmetric/hologram/issues/15
            "#{key}=\"\""

          :expression ->
            "#{key}='~Hologram.Template.AttributeValueExpression[#{value}]'"

          :literal ->
            "#{key}=\"#{value}\""

        end
      end)
      |> Enum.join(" ")

    "<#{tag_name} #{attrs}>"
  end

  def encode({:end_tag, tag_name}), do: "</#{tag_name}>"

  def encode({:text_tag, str}), do: str

  def encode({:symbol, symbol}), do: to_string(symbol)

  def encode({:string, str}), do: str

  def encode({:whitespace, char}), do: char

  def encode(nil), do: ""
end
