defmodule Hologram.Template.Tokenizer do
  @type token :: {:string | :symbol | :whitespace, String.t()}

  @doc """
  Splits template markup into a list of tokens.

  ## Examples

      iex> tokenize("<span>aaa bbb</span>")
      [
        symbol: "<",
        string: "span",
        symbol: ">",
        string: "aaa",
        whitespace: " ",
        string: "bbb",
        symbol: "</",
        string: "span",
        symbol: ">"
      ]
  """
  @spec tokenize(String.t()) :: list(token)
  def tokenize(markup)

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

  def tokenize("\\\#{" <> rest) do
    [{:symbol, "\\\#{"} | tokenize(rest)]
  end

  def tokenize("\#{" <> rest) do
    [{:symbol, "\#{"} | tokenize(rest)]
  end

  def tokenize("#" <> rest) do
    [{:symbol, "#"} | tokenize(rest)]
  end

  def tokenize("\\${" <> rest) do
    [{:symbol, "\\${"} | tokenize(rest)]
  end

  def tokenize("${" <> rest) do
    [{:symbol, "${"} | tokenize(rest)]
  end

  def tokenize("$" <> rest) do
    [{:symbol, "$"} | tokenize(rest)]
  end

  def tokenize("=" <> rest) do
    [{:symbol, "="} | tokenize(rest)]
  end

  def tokenize("\\\"" <> rest) do
    [{:symbol, "\\\""} | tokenize(rest)]
  end

  def tokenize("\"" <> rest) do
    [{:symbol, "\""} | tokenize(rest)]
  end

  def tokenize("\\'" <> rest) do
    [{:symbol, "\\'"} | tokenize(rest)]
  end

  def tokenize("'" <> rest) do
    [{:symbol, "'"} | tokenize(rest)]
  end

  def tokenize("\\`" <> rest) do
    [{:symbol, "\\`"} | tokenize(rest)]
  end

  def tokenize("`" <> rest) do
    [{:symbol, "`"} | tokenize(rest)]
  end

  def tokenize("\\{" <> rest) do
    [{:symbol, "\\{"} | tokenize(rest)]
  end

  def tokenize("{#raw}" <> rest) do
    [{:symbol, "{#raw}"} | tokenize(rest)]
  end

  def tokenize("{#" <> rest) do
    [{:symbol, "{#"} | tokenize(rest)]
  end

  def tokenize("{/raw}" <> rest) do
    [{:symbol, "{/raw}"} | tokenize(rest)]
  end

  def tokenize("{/" <> rest) do
    [{:symbol, "{/"} | tokenize(rest)]
  end

  def tokenize("{" <> rest) do
    [{:symbol, "{"} | tokenize(rest)]
  end

  def tokenize("\\}" <> rest) do
    [{:symbol, "\\}"} | tokenize(rest)]
  end

  def tokenize("}" <> rest) do
    [{:symbol, "}"} | tokenize(rest)]
  end

  def tokenize("</" <> rest) do
    [{:symbol, "</"} | tokenize(rest)]
  end

  def tokenize("<" <> rest) do
    [{:symbol, "<"} | tokenize(rest)]
  end

  def tokenize("/>" <> rest) do
    [{:symbol, "/>"} | tokenize(rest)]
  end

  def tokenize(">" <> rest) do
    [{:symbol, ">"} | tokenize(rest)]
  end

  def tokenize("/" <> rest) do
    [{:symbol, "/"} | tokenize(rest)]
  end

  def tokenize("\\" <> rest) do
    [{:symbol, "\\"} | tokenize(rest)]
  end

  def tokenize(rest) do
    excluded_chars = Regex.escape(" \n\r\t#$=\"'`{}<>/\\")
    regex = ~r/\A([^#{excluded_chars}]+)(.*)\z/s
    [_full_capture, value, rest] = Regex.run(regex, rest)
    [{:string, value} | tokenize(rest)]
  end
end
