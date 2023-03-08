defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  import Hologram.Test.Fixtures.Compiler.Transformer.Module2
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2, as: InnerAlias

  defmacro macro_call_1 do
    quote do
      macro_2a()
    end
  end

  defmacro macro_call_2 do
    quote do
      macro_2a
    end
  end

  defmacro macro_call_3 do
    quote do
      InnerAlias.macro_2a()
    end
  end

  defmacro macro_call_4 do
    quote do
      my_fun()
    end
  end

  defmacro macro_call_5 do
    quote do
      my_fun(1, 2)
    end
  end

  defmacro macro_call_6 do
    quote do
      a.x()
    end
  end

  defmacro macro_call_7 do
    quote do
      a.x(1, 2)
    end
  end

  defmacro macro_call_8 do
    quote do
      InnerAlias.my_fun()
    end
  end

  defmacro macro_call_9 do
    quote do
      OuterAlias.my_fun()
    end
  end

  defmacro macro_call_10 do
    quote do
      InnerAlias.my_fun(1, 2)
    end
  end

  defmacro macro_call_11 do
    quote do
      InnerAlias.my_fun
    end
  end

  defmacro macro_call_12 do
    quote do
      OuterAlias.my_fun
    end
  end

  defmacro macro_call_13 do
    quote do
      OuterAlias.my_fun(1, 2)
    end
  end

  defmacro macro_call_14 do
    quote do
      macro_2b(1, 2)
    end
  end

  defmacro macro_module_attribute_operator_1 do
    quote do
      @my_attr
    end
  end
end
