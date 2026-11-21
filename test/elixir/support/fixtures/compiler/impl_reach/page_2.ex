# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page2 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Struct2

  route "/hologram-test-fixtures-compiler-impl-reach-page2"

  layout Hologram.Test.Fixtures.LayoutFixture

  derived :result, :any, fn -> Protocol.run(%Struct2{}) end

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end
end
