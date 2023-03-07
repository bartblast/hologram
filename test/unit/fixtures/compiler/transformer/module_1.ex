defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  import Hologram.Test.Fixtures.Compiler.Transformer.Module2
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2, as: InnerAlias

  defmacro macro_1a do
    quote do
      macro_2a()
    end
  end

  defmacro macro_1b do
    quote do
      macro_2a
    end
  end

  defmacro macro_1c do
    quote do
      InnerAlias.macro_2a()
    end
  end

  defmacro macro_1d do
    quote do
      my_fun()
    end
  end

  defmacro macro_1e do
    quote do
      my_fun(1, 2)
    end
  end

  defmacro macro_1f do
    quote do
      a.x()
    end
  end

  defmacro macro_1g do
    quote do
      a.x(1, 2)
    end
  end

  defmacro macro_1h do
    quote do
      InnerAlias.my_fun()
    end
  end

  defmacro macro_1i do
    quote do
      OuterAlias.my_fun()
    end
  end

  defmacro macro_1j do
    quote do
      InnerAlias.my_fun(1, 2)
    end
  end

  defmacro macro_1k do
    quote do
      InnerAlias.my_fun
    end
  end

  defmacro macro_1l do
    quote do
      OuterAlias.my_fun
    end
  end

  defmacro macro_1m do
    quote do
      OuterAlias.my_fun(1, 2)
    end
  end

  defmacro macro_1n do
    quote do
      macro_2b(1, 2)
    end
  end
end
