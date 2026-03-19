# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module43 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    Module43 template
    """
  end

  def command(:command_43a, _params, server) do
    server
  end
end
