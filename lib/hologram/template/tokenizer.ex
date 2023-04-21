defmodule Hologram.Template.Tokenizer do
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
  @spec tokenize(String.t()) :: list({:string | :symbol | :whitespace, String.t()})
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
    [{:symbol, "</"} | tokenize(rest)]
  end

  def tokenize("/>" <> rest) do
    [{:symbol, "/>"} | tokenize(rest)]
  end

  def tokenize("<" <> rest) do
    [{:symbol, "<"} | tokenize(rest)]
  end

  def tokenize(">" <> rest) do
    [{:symbol, ">"} | tokenize(rest)]
  end

  def tokenize("/" <> rest) do
    [{:symbol, "/"} | tokenize(rest)]
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

  def tokenize("\\" <> rest) do
    [{:symbol, "\\"} | tokenize(rest)]
  end

  def tokenize(rest) do
    excluded_chars = " \n\r\t<>/=\"{}\\" |> Regex.escape()
    regex = ~r/\A([^#{excluded_chars}]+)(.*)\z/s
    [_full_capture, token, rest] = Regex.run(regex, rest)
    [{:string, token} | tokenize(rest)]
  end
end
