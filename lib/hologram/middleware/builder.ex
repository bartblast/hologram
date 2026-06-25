defmodule Hologram.Middleware.Builder do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Hologram.Middleware.Builder, only: [middleware: 1, middleware: 2]

      Module.register_attribute(__MODULE__, :__middleware__, accumulate: true)

      @before_compile Hologram.Middleware.Builder
    end
  end

  @doc """
  Attaches a middleware step to the page or component.

  The target is either a `Hologram.Middleware` module (run as `Mod.call(server, opts)`) or an atom
  naming a public `target(server, opts)` function on the host module. Declarations accumulate in
  order, including those injected by a base module's `__using__`, so composition is additive.
  """
  defmacro middleware(target, opts \\ []) do
    quote do
      @__middleware__ {unquote(target), unquote(opts)}
    end
  end

  defmacro __before_compile__(env) do
    entries =
      env.module
      |> Module.get_attribute(:__middleware__)
      |> Enum.reverse()
      |> Enum.map(&compile_entry(env, &1))

    quote do
      def __middleware__, do: unquote(entries)
    end
  end

  defp compile_entry(env, {target, opts}) do
    capture =
      if module_target?(target) do
        quote do: Function.capture(unquote(target), :call, 2)
      else
        ensure_function_middleware!(env, target)
        quote do: Function.capture(__MODULE__, unquote(target), 2)
      end

    quote do: {unquote(capture), unquote(Macro.escape(opts))}
  end

  defp ensure_function_middleware!(env, target) do
    unless Module.defines?(env.module, {target, 2}, :def) do
      raise ArgumentError,
            "middleware #{inspect(target)} requires a public #{target}/2 function in " <>
              inspect(env.module)
    end
  end

  defp module_target?(target) do
    is_atom(target) and match?("Elixir." <> _rest, Atom.to_string(target))
  end
end
