defmodule Hologram.Test.Fixtures.Controller.Module34 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module34"

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def template do
    ~HOLO""
  end
end
