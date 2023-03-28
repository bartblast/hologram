defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  defmacro macro_module_attribute_definition do
    quote do
      @my_attr 987
    end
  end

  defmacro macro_module_attribute_operator do
    quote do
      @my_attr
    end
  end

  defmacro macro_symbol do
    quote do
      my_symbol
    end
  end
end
