defmodule Hologram.JS do
  @moduledoc false

  alias Hologram.Compiler.AST

  defmacro __using__(_opts) do
    quote do
      register_js_bindings_accumulator()
    end
  end

  @doc """
  Executes JavaScript code.
  Server-side implementation is just a dummy. The actual implementation is on the client-side.
  """
  @spec exec(String.t()) :: String.t()
  def exec(code), do: code

  @doc """
  Returns the AST of code that registers __js_bindings__ module attribute.
  """
  @spec register_js_bindings_accumulator() :: AST.t()
  def register_js_bindings_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__js_bindings__, accumulate: true)
    end
  end

  @doc """
  Provides a convenient syntax for executing JavaScript code using the ~JS sigil.
  """
  @spec sigil_JS(String.t(), []) :: String.t()
  def sigil_JS(code, []), do: exec(code)
end
