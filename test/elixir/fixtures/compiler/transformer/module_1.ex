defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  defmacro macro_module_attribute_definition_1 do
    quote do
      @my_attr 987
    end
  end

  defmacro macro_module_attribute_operator_1 do
    quote do
      @my_attr
    end
  end
end
