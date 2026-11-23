# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page6 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Struct4

  route "/hologram-test-fixtures-compiler-impl-reach-page6"

  layout Hologram.Test.Fixtures.LayoutFixture

  derived :result, :any, fn -> %Struct4{} end

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end
end
