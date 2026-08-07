defmodule HologramFeatureTests.StacktraceFixture do
  # The function raises on every path, so it never returns.
  @dialyzer {:no_return, raise_error: 1}

  def raise_error(x) do
    {x, raise("raised in a remote function")}
  end
end
