defmodule Hologram.Test.Fixtures.Runtime.Connection.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-connection-module2"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Module2 template"
  end
end
