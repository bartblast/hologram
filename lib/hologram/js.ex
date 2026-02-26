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
      Hologram.JS.call(unquote(receiver), unquote(method), unquote(args), unquote(module))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec call(any(), atom(), list(), module()) :: any()
  def call(_receiver, _method, _args, _caller_module), do: __server_pass_through__()

  @doc """
  Calls an async method on a JS receiver and awaits the result.
  """
  defmacro call_async(receiver, method, args) do
    module = __CALLER__.module

    quote do
      Hologram.JS.call_async(
        unquote(receiver),
        unquote(method),
        unquote(args),
        unquote(module)
      )
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec call_async(any(), atom(), list(), module()) :: any()
  def call_async(_receiver, _method, _args, _caller_module), do: __server_pass_through__()

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
      Hologram.JS.get(unquote(receiver), unquote(property), unquote(module))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec get(any(), atom(), module()) :: any()
  def get(_receiver, _property, _caller_module), do: __server_pass_through__()

  @doc """
  Imports a JS export and binds it to a name that can be used as a receiver in other JS functions.

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
      Hologram.JS.new(unquote(class), unquote(args), unquote(module))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec new(any(), list(), module()) :: any()
  def new(_class, _args, _caller_module), do: __server_pass_through__()

  @doc """
  Sets a property on a JS receiver.
  """
  defmacro set(receiver, property, value) do
    module = __CALLER__.module

    quote do
      Hologram.JS.set(
        unquote(receiver),
        unquote(property),
        unquote(value),
        unquote(module)
      )
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec set(any(), atom(), any(), module()) :: any()
  def set(receiver, _property, _value, _caller_module), do: receiver

  @doc """
  Provides a convenient syntax for executing JavaScript code using the ~JS sigil.
  """
  @spec sigil_JS(String.t(), []) :: :ok
  def sigil_JS(code, []), do: exec(code)

  @doc """
  Returns the JavaScript type of a value.
  """
  defmacro typeof(value) do
    module = __CALLER__.module

    quote do
      Hologram.JS.typeof(unquote(value), unquote(module))
    end
  end

  # Server-side pass-through; implemented in JavaScript.
  @doc false
  @spec typeof(any(), module()) :: any()
  def typeof(_value, _caller_module), do: __server_pass_through__()

  # Returns :ok at runtime, but the use of Application.get_env/3 makes the return type
  # opaque to the Elixir type checker. This prevents false positive type warnings when
  # end users compare JS interop results with specific values (e.g. in case/cond expressions).
  # On the client side, these functions are replaced by actual JavaScript implementations.
  defp __server_pass_through__ do
    Application.get_env(:hologram, :__server_pass_through__, :ok)
  end
end
