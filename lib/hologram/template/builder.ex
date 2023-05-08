defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.AST
  alias Hologram.Template.Helpers

  def build(tags) do
    {code, _last_tag_type} =
      tags
      |> Enum.reduce({"", nil}, fn tag, {code_acc, last_tag_type} ->
        current_tag_type = elem(tag, 0)
        current_tag_code = render_code(tag)
        new_code_acc = append_code(code_acc, current_tag_code, last_tag_type)

        {new_code_acc, current_tag_type}
      end)

    AST.for_code("[#{code}]")
  end

  defp append_code(code_acc, code, last_tag_type) when last_tag_type in [:end_tag, :text] do
    code_acc <> ", " <> code
  end

  defp append_code(code_acc, code, _last_tag_type) do
    code_acc <> code
  end

  defp render_code({:end_tag, _tag_name}) do
    "]}"
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
