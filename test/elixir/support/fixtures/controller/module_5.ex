defmodule Hologram.Test.Fixtures.Controller.Module5 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-controller-module5"

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def template do
    ~HOLO"Module5 page"
  end
end
