defmodule Hologram.Test.Fixtures.Compiler.Processor.Module15 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.Processor.Module6
  alias Hologram.Test.Fixtures.Compiler.Processor.Module7

  def template do
    ~H"""
    <Module6></Module6>
    test_text
    <Module7></Module7>
    """
  end
end
