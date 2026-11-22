# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page5 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Struct3

  route "/hologram-test-fixtures-compiler-impl-reach-page5"

  layout Hologram.Test.Fixtures.LayoutFixture

  derived :result, :any, fn -> Protocol.run(%Struct3{}) end

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end
end
