defmodule Hologram.Commons.TestUtils do
  alias Hologram.Commons.IntegerUtils

  defdelegate pid(str), to: IEx.Helpers
  defdelegate port(str), to: IEx.Helpers
  defdelegate ref(str), to: IEx.Helpers

  @doc """
  Builds an error message for ArgumentError.
  """
  @spec build_argument_error_msg(integer(), String.t()) :: String.t()
  def build_argument_error_msg(arg_idx, blame) do
    """
    errors were found at the given arguments:

      * #{IntegerUtils.ordinal(arg_idx)} argument: #{blame}
    """
  end

  @doc """
  Returns the given argument.
  It prevents compiler warnings in tests when the given value is not permitted is specific situation.
  """
  @spec wrap_term(any) :: any
  def wrap_term(value) do
    value
  end
end
