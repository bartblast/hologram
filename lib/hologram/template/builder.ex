defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.AST

  def build(tags) do
    {code, _last_tag} =
      tags
      |> Enum.reduce({"", nil}, &render_tag/2)

    AST.for_code("[#{code}]")
  end

  defp append_code(code_acc, code, last_tag) when last_tag in [nil, :end_tag] do
    code_acc <> code
  end

  defp append_code(code_acc, code, _last_tag) do
    code_acc <> ", " <> code
  end

  defp render_tag({:text, str}, {code_acc, last_tag}) do
    tag_code = "{:text, \"#{str}\"}"
    new_code_acc = append_code(code_acc, tag_code, last_tag)

    {new_code_acc, :text}
  end
end
