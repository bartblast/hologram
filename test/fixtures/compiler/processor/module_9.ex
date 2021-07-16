defmodule Hologram.Test.Fixtures.Compiler.Processor.Module9 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Processor.Module6, warn: false
  alias Hologram.Test.Fixtures.Compiler.Processor.Module7, warn: false

  def template do
    ~H"""
    <Module6></Module6>
    test_text
    <Module7></Module7>
    """
  end
end
