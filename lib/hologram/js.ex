defmodule Hologram.JS do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Hologram.JS, only: [js_import: 2]

      @before_compile Hologram.JS

      Module.register_attribute(__MODULE__, :__js_imports__, accumulate: true)
    end
  end

  defmacro __before_compile__(env) do
    env.module
    |> Module.get_attribute(:__js_imports__)
    |> Enum.frequencies_by(& &1.as)
    |> Enum.each(fn {name, count} ->
      if count > 1 do
        raise Hologram.CompileError,
          message: "duplicate JS binding name \"#{name}\" in #{inspect(env.module)}"
      end
    end)

    quote do
      @doc """
      Returns the list of JS imports declared with js_import/2 in the module.
      """
      @spec __js_imports__() :: list(map)
      def __js_imports__, do: Enum.reverse(@__js_imports__)
    end
  end

  @doc """
  Executes JavaScript code.
  Server-side implementation is just a dummy. The actual implementation is on the client-side.
  """
  @spec exec(String.t()) :: String.t()
  def exec(code), do: code

  @doc """
  Imports a JS export and binds it to a name available via JS.ref/1.

  ## Examples

      js_import "Chart", from: "chart.js"
      js_import "Chart", from: "chart.js", as: "MyChart"
  """
  defmacro js_import(export, opts) do
    from = Keyword.fetch!(opts, :from)
    as = Keyword.get(opts, :as, export)

    quote do
      @__js_imports__ %{export: unquote(export), from: unquote(from), as: unquote(as)}
    end
  end

  @doc """
  Provides a convenient syntax for executing JavaScript code using the ~JS sigil.
  """
  @spec sigil_JS(String.t(), []) :: String.t()
  def sigil_JS(code, []), do: exec(code)
end
