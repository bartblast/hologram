defmodule Hologram.Runtime.Commons do
  alias Hologram.Compiler
  alias Hologram.Template

  defmacro sigil_H(str, _) do
    module_def =
      __CALLER__.file
      |> Compiler.Parser.parse_file!()
      |> Compiler.Normalizer.normalize()
      |> Compiler.Transformer.transform(%Compiler.Context{})

    context = %Compiler.Context{
      aliases: module_def.aliases,
      imports: module_def.imports
    }

    vdom =
      str
      |> Code.eval_quoted()
      |> elem(0)
      |> Template.Parser.parse!()
      |> Template.Transformer.transform(context)
      |> Macro.escape()

    quote do
      unquote(vdom)
    end
  end
end
