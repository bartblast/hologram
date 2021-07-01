defmodule Hologram.Template.VirtualDOMTest do
  use Hologram.TestCase, async: true
  
  alias Hologram.Template.VirtualDOM
  alias Hologram.Template.VirtualDOM.ElementNode

  test "build/1" do
    module = Hologram.Test.Fixtures.Template.VirtualDOM.Module1
    assert [%ElementNode{}] = VirtualDOM.build(module)
  end
end
