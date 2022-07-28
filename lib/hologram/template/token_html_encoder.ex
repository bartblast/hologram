# TODO: test

defmodule Hologram.Template.TokenHTMLEncoder do
  def encode(arg)

  def encode(tokens) when is_list(tokens) do
    Enum.map(tokens, &encode/1)
    |> Enum.join("")
  end

  def encode({:directive, :raw_start}), do: ""
  def encode({:directive, :raw_end}), do: ""

  def encode({:string, str}), do: str

  def encode({:symbol, symbol}), do: to_string(symbol)

  def encode({:whitespace, char}), do: char

  def encode(nil), do: ""
end
