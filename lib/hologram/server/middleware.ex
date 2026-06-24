defmodule Hologram.Server.Middleware do
  @moduledoc false

  alias Hologram.Server

  @type step :: (Server.t() -> Server.t() | [step()])

  @doc """
  Runs a middleware result against the server struct.

  A `Server` struct is returned as-is (an inline result). A list of step captures is
  folded left to right over the server: each step receives the current server and
  returns either an updated server or a nested list of steps, which is expanded in
  place. Folding stops as soon as a step produces a terminal server (a non-nil
  `status`), leaving the remaining steps unrun.
  """
  @spec run(Server.t(), Server.t() | [step()]) :: Server.t()
  def run(server, result)

  def run(_server, %Server{} = result), do: result

  def run(server, steps) when is_list(steps) do
    fold(server, steps)
  end

  defp fold(server, []), do: server

  defp fold(%Server{status: status} = server, _steps) when status != nil do
    server
  end

  defp fold(server, [step | rest]) do
    server
    |> run(step.(server))
    |> fold(rest)
  end
end
