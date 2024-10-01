# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module2 do
  alias Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module3

  def fun_2a, do: :a

  def fun_2b, do: Module3.fun_3c()
end
