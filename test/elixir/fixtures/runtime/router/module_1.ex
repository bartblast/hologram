defmodule Hologram.Test.Fixtures.Runtime.Router.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-router-module1"

  layout Hologram.Test.Fixtures.Runtime.Router.Module2

  @impl Page
  def template do
    ~H""
  end
end
