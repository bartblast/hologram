defmodule Hologram.Compiler.TypeOperatorEncoder do
  alias Hologram.Compiler.{Context, Generator}

  # DEFER: implement other type modifiers
  def encode(value, :binary, %Context{} = context, opts) do
    value = Generator.generate(value, context, opts)
    "Elixir.typeOperator(#{value}, 'binary')"
  end
end
