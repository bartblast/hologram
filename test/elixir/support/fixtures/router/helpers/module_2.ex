defmodule Hologram.Test.Fixtures.Router.Helpers.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-helpers-module2/:param_1/:param_2"

  param :param_1
  param :param_2

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~H""
  end
end
