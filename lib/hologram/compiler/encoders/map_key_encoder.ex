defprotocol Hologram.Compiler.MapKeyEncoder do
  def encode(ir, context, opts)
end


# TODO: delete
defmodule Hologram.Compiler.MapKeyGenerator do
#   alias Hologram.Compiler.IR.{AtomType, BooleanType, IntegerType, StringType}

def generate(_, _), do: nil
#   def generate(%StringType{value: value}, _) do
#     "~string[#{value}]"
#   end
end
