defmodule Hologram.Test.Fixtures.Connection.Module5 do
  use Hologram.Page

  route "/hologram-test-fixtures-connection-module5"

  layout Hologram.Test.Fixtures.Connection.Module4

  @impl Page
  def template do
    ~HOLO"page Module5 template"
  end
end
