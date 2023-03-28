defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  import Hologram.Test.Fixtures.Compiler.Transformer.Module2

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

  defmacro macro_call_15 do
    quote do
      @my_attr.my_fun()
    end
  end

  defmacro macro_call_16 do
    quote do
      @my_attr.my_fun(1, 2)
    end
  end

  defmacro macro_call_17 do
    quote do
      (3 + 4).my_fun()
    end
  end

  defmacro macro_call_18 do
    quote do
      (3 + 4).my_fun(1, 2)
    end
  end

  defmacro macro_call_19 do
    quote do
      __MODULE__.my_fun
    end
  end

  defmacro macro_call_20 do
    quote do
      __MODULE__.my_fun()
    end
  end

  defmacro macro_call_21 do
    quote do
      __MODULE__.my_fun(1, 2)
    end
  end

  defmacro macro_call_22 do
    quote do
      :my_module.my_fun
    end
  end

  defmacro macro_call_23 do
    quote do
      :my_module.my_fun()
    end
  end

  defmacro macro_call_24 do
    quote do
      :my_module.my_fun(1, 2)
    end
  end

  defmacro macro_call_25 do
    quote do
      "#{my_var}"
    end
  end
end
