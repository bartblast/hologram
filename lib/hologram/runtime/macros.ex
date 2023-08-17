defmodule Hologram.Runtime.Macros do
  alias Hologram.Template.Builder

  defmacro sigil_H({:<<>>, _meta, [markup]}, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defmacro sigil_H(markup, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defp build_h_sigil_ast(markup) do
    quote do
      fn var!(data) ->
        _fix_unused_data_var = var!(data)
        unquote(Builder.build(markup))
      end
    end
  end
end
