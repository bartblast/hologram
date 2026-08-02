# credo:disable-for-this-file Credo.Check.Readability.Specs
defimpl Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1, for: Integer do
  def my_fun(_data), do: :ok
end
