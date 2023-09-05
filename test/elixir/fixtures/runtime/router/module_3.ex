defmodule Hologram.Test.Fixtures.Runtime.Router.Module3 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-router-module3/:aaa/ccc/:bbb"

  param :aaa
  param :bbb

  layout Hologram.Test.Fixtures.Runtime.Router.Module2

  @impl Page
  def template do
    ~H""
  end
end
