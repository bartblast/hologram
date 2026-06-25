defmodule Hologram.Middleware do
  @moduledoc """
  The behaviour and construct for module middleware - reusable, server-side steps that run before
  a page renders and before a command executes.

  `use Hologram.Middleware` makes a module a middleware, written one of two ways.

  A **leaf** implements the `call/2` callback, receiving the `Hologram.Server` struct and the
  declared options and returning a (possibly transformed) server struct:

      defmodule MyApp.RequireAdmin do
        use Hologram.Middleware

        @impl Hologram.Middleware
        def call(server, _opts) do
          if admin?(server) do
            server
          else
            put_status(server, :forbidden)
          end
        end
      end

  A **group** declares a sub-chain with the `middleware` macros and has its `call/2` generated to
  fold that chain, so the group is itself an ordinary middleware that attaches as a single unit:

      defmodule MyApp.AdminStack do
        use Hologram.Middleware

        middleware MyApp.RequireLogin
        middleware MyApp.RequireAdmin
        middleware MyApp.AuditLog
      end

  `use Hologram.Middleware` injects the behaviour, the `Hologram.Server` response helpers (so a
  leaf writes `put_status/2`, `put_redirect/2`, `put_stash/3`, ... without qualification), and the
  `middleware` declaration macros. The `call/2` is generated only for a module that declared
  middleware and did not define its own - a module that does neither raises the standard
  "call/2 not implemented" behaviour warning, so a forgotten gate never silently passes.

  A middleware module is attached to a page or component with the `middleware` macros.
  """

  alias Hologram.Server

  @doc """
  Runs the middleware against the server struct.

  Receives the server and the declared options, and returns the server struct - possibly
  carrying a terminal response that short-circuits the remaining middleware.
  """
  @callback call(server :: Server.t(), opts :: term()) :: Server.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Hologram.Middleware

      use Hologram.Middleware.Builder

      import Hologram.Server, only: unquote(Hologram.Server.__helper_imports__())

      @before_compile Hologram.Middleware
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    declared? = match?([_entry | _rest], Module.get_attribute(env.module, :__middleware__))
    defines_call? = Module.defines?(env.module, {:call, 2}, :def)

    if declared? and not defines_call? do
      quote do
        @impl Hologram.Middleware
        def call(server, _opts) do
          Hologram.Server.Middleware.run(server, __middleware__())
        end
      end
    end
  end
end
