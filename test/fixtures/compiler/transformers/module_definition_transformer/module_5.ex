defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module5 do
  defmacro test_macro(a) do
    quote do
      def test_function(b) do
        unquote(a) + b
      end
    end
  end
end
