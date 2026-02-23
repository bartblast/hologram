defmodule Hologram.JS do
  alias Hologram.Reflection

  defmacro __using__(_opts) do
    quote do
      import Hologram.JS, only: [js_import: 2, sigil_JS: 2]

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
  Calls a method on a JS receiver.
  """
  defmacro call(receiver, method, args) do
    module = __CALLER__.module

    quote do
      Hologram.JS.call(unquote(module), unquote(receiver), unquote(method), unquote(args))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec call(module(), any(), String.t(), list()) :: :ok
  def call(_caller_module, _receiver, _method, _args), do: :ok

  # Server-side pass-through; implemented in JavaScript.
  @doc """
  Executes JavaScript code.
  """
  @spec exec(String.t()) :: :ok
  def exec(_code), do: :ok

  @doc """
  Gets a property from a JS receiver.
  """
  defmacro get(receiver, property) do
    module = __CALLER__.module

    quote do
      Hologram.JS.get(unquote(module), unquote(receiver), unquote(property))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec get(module(), any(), atom()) :: :ok
  def get(_caller_module, _receiver, _property), do: :ok

  @doc """
  Imports a JS export and binds it to a name available via JS.ref/1.

  ## Examples

      js_import :Chart, from: "chart.js"
      js_import :Chart, from: "chart.js", as: :MyChart
  """
  defmacro js_import(export, opts) do
    from = Keyword.fetch!(opts, :from)
    as = Keyword.get(opts, :as, export)

    quote do
      from = unquote(from)

      resolved_from =
        if String.starts_with?(from, "./") or String.starts_with?(from, "../") do
          [Reflection.root_dir(), "assets", "js", from]
          |> Path.join()
          |> Path.expand()
        else
          from
        end

      @__js_imports__ %{
        export: Atom.to_string(unquote(export)),
        from: resolved_from,
        as: Atom.to_string(unquote(as))
      }
    end
  end

  @doc """
  Instantiates a JS class.
  """
  defmacro new(class, args) do
    module = __CALLER__.module

    quote do
      Hologram.JS.new(unquote(module), unquote(class), unquote(args))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec new(module(), any(), list()) :: :ok
  def new(_caller_module, _class, _args), do: :ok

  @doc """
  Provides a convenient syntax for executing JavaScript code using the ~JS sigil.
  """
  @spec sigil_JS(String.t(), []) :: :ok
  def sigil_JS(code, []), do: exec(code)
end
