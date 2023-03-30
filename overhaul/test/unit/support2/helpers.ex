defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.AST

  defdelegate ast(code), to: AST, as: :for_code
end
