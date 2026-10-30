# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module52 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.LayoutWithRuntime

  route "/hologram-test-fixtures-controller-module52"

  layout LayoutWithRuntime

  @impl Page
  def init(_params, component, server) do
    row = %Module15{
      id: "test-id-52",
      label: "Report",
      secret_note: "note_secret_v7",
      token: "tok_P4qW"
    }

    {put_state(component, :row, row), server}
  end

  @impl Page
  def template do
    ~HOLO"Module52"
  end
end
