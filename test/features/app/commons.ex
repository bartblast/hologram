defmodule HologramFeatureTests.Commons do
  @doc """
  Returns the given term.
  It prevents compiler warnings when the given term is not permitted is specific situations.
  """
  @spec wrap_term(any) :: any
  def wrap_term(term), do: term
end
