defmodule HologramFeatureTests.Commons do
  defdelegate pid(str), to: IEx.Helpers
  defdelegate port(str), to: IEx.Helpers
  defdelegate ref(str), to: IEx.Helpers

  @doc """
  Returns the given term.
  It prevents compiler warnings when the given term is not permitted is specific situations.
  """
  @spec wrap_term(any) :: any
  def wrap_term(term), do: term
end
