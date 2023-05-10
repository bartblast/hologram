defmodule Hologram.Template.VDOMTree do
  alias Hologram.Compiler.AST
  alias Hologram.Template.Helpers
  alias Hologram.Template.Parser

  @doc """
  Builds the AST of Elixir code that creates the VDOM tree representation for the given template's parsed tags list.

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

    "[#{code}]"
    |> AST.for_code()
    |> substitute_module_attributes()
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
    "{:expression, #{expr_str}}"
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

  defp substitute_module_attributes({:@, meta_1, [{name, _meta_2, _args}]}) do
    {{:., meta_1, [{:data, meta_1, nil}, name]}, [{:no_parens, true} | meta_1], []}
  end

  defp substitute_module_attributes(ast) when is_list(ast) do
    Enum.map(ast, &substitute_module_attributes/1)
  end

  defp substitute_module_attributes(ast) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.map(&substitute_module_attributes/1)
    |> List.to_tuple()
  end

  defp substitute_module_attributes(ast), do: ast
end
