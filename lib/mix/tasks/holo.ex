defmodule Mix.Tasks.Holo do
  @moduledoc """
  Starts the application with Hologram enabled.

      $ mix holo
  """

  use Mix.Task

  @doc false
  @impl Mix.Task
  def run(args) do
    System.put_env("HOLOGRAM_START", "1")
    Mix.Tasks.Phx.Server.run(args)
  end
end
