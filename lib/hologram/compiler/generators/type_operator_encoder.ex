defmodule Hologram.Compiler.TypeOperatorEncoder do
  alias Hologram.Compiler.{Context, Generator, Opts}

  # DEFER: implement other type modifiers
  def encode(value, :binary, %Context{} = context, %Opts{} = opts) do
    value = Generator.generate(value, context, opts)
    "Elixir_Kernel_SpecialForms.$type(#{value}, 'binary')"
  end
end
