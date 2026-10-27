# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module39 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Controller.Module40

  route "/hologram-test-fixtures-controller-module39"

  layout Module40

  @impl Page
  def template do
    ~HOLO"Module39"
  end
end
