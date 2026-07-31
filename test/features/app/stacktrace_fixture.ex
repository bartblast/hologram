defmodule HologramFeatureTests.StacktraceFixture do
  def raise_error(x) do
    {x, raise("raised in a remote function")}
  end
end
