defmodule Hologram.Template.OldParser do
  use Hologram.Commons.Parser

  @impl Hologram.Commons.Parser
  def parse(markup) do
    result =
      remove_doctype(markup)
      |> String.trim()
      |> wrap_root_around()
      |> fix_quotes()
      |> Saxy.SimpleForm.parse_string()

    case result do
      {:ok, {"root", [], nodes}} ->
        {:ok, nodes}

      _ ->
        result
    end
  end

  defp fix_quotes(str) do
    regex = ~r/=(\{.+\})/U
    Regex.replace(regex, str, "=\"\\1\"")
  end

  defp remove_doctype(markup) do
    regex = ~r/^\s*<!DOCTYPE[^>]*>\s*/i
    String.replace(markup, regex, "")
  end

  defp wrap_root_around(markup) do
    "<root>" <> markup <> "</root>"
  end
end
