defmodule Hologram.Middleware do
  @moduledoc """
  The behaviour for module middleware - reusable, server-side steps that run before a page
  renders and before a command executes.

  A middleware module implements `call/2`, receiving the `Hologram.Server` struct and the
  declared options and returning a (possibly transformed) server struct.

  `use Hologram.Middleware` declares the behaviour and imports the `Hologram.Server` response
  helpers so the module can build responses (`put_status/2`, `put_redirect/2`, `put_stash/3`,
  ...) without qualification.

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
      use Hologram.Server.Helpers

      @behaviour Hologram.Middleware
    end
  end
end
