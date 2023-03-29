defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2, as: InnerAlias

  defmacro macro_alias_1 do
    quote do
      Aaa.Bbb
    end
  end

  defmacro macro_alias_2 do
    quote do
      InnerAlias
    end
  end

  defmacro macro_anonymous_function_call_1 do
    quote do
      test.()
    end
  end

  defmacro macro_anonymous_function_call_2 do
    quote do
      test.(1, 2)
    end
  end

  defmacro macro_dot_operator_1 do
    quote do
      abc.x
    end
  end

  defmacro macro_dot_operator_2 do
    quote do
      @abc.x
    end
  end

  defmacro macro_dot_operator_3 do
    quote do
      (3 + 4).x
    end
  end

  defmacro macro_env_pseudo_variable do
    quote do
      __ENV__
    end
  end

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

  defmacro macro_module_pseudo_variable do
    quote do
      __MODULE__
    end
  end

  defmacro macro_symbol do
    quote do
      my_symbol
    end
  end
end
