# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Page.Module14 do
  use Hologram.Page

  route "/hologram-test-fixtures-page-module14"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end

  # Read in a COMMAND handler, which runs on the server - nothing of this reaches a bundle, so the
  # SQL surface is where it belongs.
  @impl Page
  def command(:read_with_sql, _params, server) do
    put_action(server, :done, result: Hologram.DB.sql("SELECT 1"))
  end
end
