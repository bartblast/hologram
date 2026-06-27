defmodule Hologram.Server.Middleware do
  @moduledoc false

  alias Hologram.Server

  @type middleware :: {(Server.t(), term() -> Server.t()), term()}

  @doc """
  Folds a middleware chain over the server struct.

  Each `{capture, opts}` middleware is applied left to right as `capture.(server, opts)`, threading the
  returned server into the next middleware. Folding stops as soon as a middleware produces a terminal
  server (a non-nil `status`), leaving the remaining middlewares unrun.
  """
  @spec run(Server.t(), [middleware()]) :: Server.t()
  def run(server, chain)

  def run(%Server{status: status} = server, _chain) when status != nil do
    server
  end

  def run(server, []), do: server

  def run(server, [{capture, opts} | rest]) do
    updated_server = capture.(server, opts)
    run(updated_server, rest)
  end
end
