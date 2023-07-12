defmodule Hologram.Test.Helpers do
  alias Hologram.Commons.PersistentLookupTable, as: PLT
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate ir(code, context), to: IR, as: :for_code

  @doc """
  Encodes Elixir source code to JavaScript source code.

  ## Examples

      iex> js("[1, :abc]")
      "Type.list([Type.integer(1), Type.atom(\"abc\")])"
  """
  @spec js(String.t()) :: String.t()
  def js(code) do
    code
    |> ir(%Context{})
    |> Encoder.encode(%Context{})
  end

  @doc """
  Waits until the specified persistent lookup table (PLT) with the given name
  is no longer running and the related ETS table no longer exists.

  ## Examples

      iex> wait_for_plt_cleanup(:my_plt)
      true
  """
  @spec wait_for_plt_cleanup(atom) :: :ok
  def wait_for_plt_cleanup(name) do
    if PLT.running?(name) || PLT.table_exists?(name) do
      :timer.sleep(1)
      wait_for_plt_cleanup(name)
    else
      :ok
    end
  end
end
