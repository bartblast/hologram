defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.AST
  alias Hologram.Template.Helpers
  alias Hologram.Template.Parser

  @doc """
  Given template's parsed tags generates Elixir code that builds the corresponding DOM tree, and returns its AST.

  ## Examples

      iex> tags = [{:start_tag, {"div, []}}, {:text, "abc"}, {:end_tag, "div"}]
      iex> build(tags)
      [{:{}, [line: 1], [:element, "div", [], [{:text, "abc"}]]}]
  """
  @spec build(list(Parser.parsed_tag())) :: AST.t()
  def build(tags) do
    {code, _last_tag_type} =
      Enum.reduce(tags, {"", nil}, fn tag, {code_acc, last_tag_type} ->
        current_tag_type = elem(tag, 0)
        current_tag_code = render_code(tag)
        new_code_acc = append_code(code_acc, current_tag_code, last_tag_type)

        {new_code_acc, current_tag_type}
      end)

    AST.for_code("[#{code}]")
  end

  defp append_code(code_acc, code, last_tag_type)
       when last_tag_type in [:end_tag, :expression, :text] do
    code_acc <> ", " <> code
  end

  defp append_code(code_acc, code, _last_tag_type) do
    code_acc <> code
  end

  defp extract_expression_content(expr_str) do
    expr_str
    |> String.slice(1, String.length(expr_str) - 2)
    |> String.trim()
  end

  defp render_code({:block_start, "else"}) do
    "] else ["
  end

  defp render_code({:block_start, {"for", expr_str}}) do
    "(for #{extract_expression_content(expr_str)} do ["
  end

  defp render_code({:block_end, "for"}) do
    "] end)"
  end

  defp render_code({:block_start, {"if", expr_str}}) do
    "(if #{extract_expression_content(expr_str)} do ["
  end

  defp render_code({:block_end, "if"}) do
    "] end)"
  end

  defp render_code({:end_tag, _tag_name}) do
    "]}"
  end

  defp render_code({:expression, expr_str}) do
    "{:expression, #{extract_expression_content(expr_str)}}"
  end

  defp render_code({:start_tag, {tag_name, attributes}}) do
    tag_type = Helpers.tag_type(tag_name)

    attributes_code =
      Enum.map_join(attributes, ", ", fn {name, value_parts} ->
        "{\"#{name}\", [" <> Enum.map_join(value_parts, ", ", &render_code/1) <> "]}"
      end)

    "{:#{tag_type}, \"#{tag_name}\", [#{attributes_code}], ["
  end

  defp render_code({:text, str}) do
    "{:text, \"#{str}\"}"
  end
end
