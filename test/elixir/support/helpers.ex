defmodule Hologram.Test.Helpers do
  alias Hologram.Commons.PLT
  alias Hologram.Commons.ProcessUtils
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
  Waits until the specified persistent lookup table (PLT)
  is no longer running and the related ETS table no longer exists.

  ## Examples

      iex> wait_for_plt_cleanup(:my_plt)
      :ok
  """
  @spec wait_for_plt_cleanup(atom) :: :ok
  def wait_for_plt_cleanup(name) do
    wait_for_process_cleanup(name)

    if PLT.table_exists?(name) do
      :timer.sleep(1)
      wait_for_plt_cleanup(name)
    else
      :ok
    end
  end

  @doc """
  Waits until the specified process is no longer running.

  ## Examples

      iex> wait_for_process_cleanup(:my_process)
      :ok
  """
  @spec wait_for_process_cleanup(atom) :: :ok
  def wait_for_process_cleanup(name) do
    if ProcessUtils.running?(name) do
      :timer.sleep(1)
      wait_for_process_cleanup(name)
    else
      :ok
    end
  end
end
