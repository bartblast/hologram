defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.IR

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate ir(code), to: IR, as: :for_code
end
