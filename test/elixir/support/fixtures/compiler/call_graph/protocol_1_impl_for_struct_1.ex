# credo:disable-for-this-file Credo.Check.Readability.Specs
defimpl Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1,
  for: Hologram.Test.Fixtures.Compiler.CallGraph.Struct1 do
  def my_fun(_data), do: :ok
end
