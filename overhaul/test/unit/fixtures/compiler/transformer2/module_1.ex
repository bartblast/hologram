defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2, as: InnerAlias

  defmacro macro_call_3 do
    quote do
      InnerAlias.macro_2a()
    end
  end
end
