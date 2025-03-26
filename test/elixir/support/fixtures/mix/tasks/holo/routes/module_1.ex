defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Routes.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-mix-tasks-holo-routes-module1"

  layout Hologram.Test.Fixtures.Mix.Tasks.Holo.Routes.Module2

  @impl Page
  def template do
    ~HOLO""
  end
end
