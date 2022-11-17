defmodule Hologram.Template.Tokenizer do
  def tokenize(""), do: []

  def tokenize(" " <> rest) do
    [{:whitespace, " "} | tokenize(rest)]
  end

  def tokenize("\n" <> rest) do
    [{:whitespace, "\n"} | tokenize(rest)]
  end

  def tokenize("\r" <> rest) do
    [{:whitespace, "\r"} | tokenize(rest)]
  end

  def tokenize("\t" <> rest) do
    [{:whitespace, "\t"} | tokenize(rest)]
  end

  def tokenize("</" <> rest) do
    [{:symbol, :"</"} | tokenize(rest)]
  end

  def tokenize("/>" <> rest) do
    [{:symbol, :"/>"} | tokenize(rest)]
  end

  def tokenize("<" <> rest) do
    [{:symbol, :<} | tokenize(rest)]
  end

  def tokenize(">" <> rest) do
    [{:symbol, :>} | tokenize(rest)]
  end

  def tokenize("/" <> rest) do
    [{:symbol, :/} | tokenize(rest)]
  end

  def tokenize("=" <> rest) do
    [{:symbol, :=} | tokenize(rest)]
  end

  def tokenize("\\\"" <> rest) do
    [{:symbol, :"\\\""} | tokenize(rest)]
  end

  def tokenize("\"" <> rest) do
    [{:symbol, :"\""} | tokenize(rest)]
  end

  def tokenize("\\{" <> rest) do
    [{:symbol, :"\\{"} | tokenize(rest)]
  end

  def tokenize("{#" <> rest) do
    [{:symbol, :"{#"} | tokenize(rest)]
  end

  def tokenize("{/" <> rest) do
    [{:symbol, :"{/"} | tokenize(rest)]
  end

  def tokenize("{" <> rest) do
    [{:symbol, :"{"} | tokenize(rest)]
  end

  def tokenize("\\}" <> rest) do
    [{:symbol, :"\\}"} | tokenize(rest)]
  end

  def tokenize("}" <> rest) do
    [{:symbol, :"}"} | tokenize(rest)]
  end

  def tokenize("\\" <> rest) do
    [{:symbol, :\\} | tokenize(rest)]
  end

  def tokenize(rest) do
    excluded_chars = " \n\r\t<>/=\"{}\\" |> Regex.escape()
    regex = ~r/\A([^#{excluded_chars}]+)(.*)\z/s
    [_, string, rest] = Regex.run(regex, rest)
    [{:string, string} | tokenize(rest)]
  end
end
