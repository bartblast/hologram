defmodule Hologram.Test.Fixtures.Compiler.Processor.Module9 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Processor.Module6
  alias Hologram.Test.Fixtures.Compiler.Processor.Module7

  def template do
    ~H"""
    <Module6></Module6>
    test_text
    <Module7></Module7>
    """
  end

  # prevent unused alias compiler warning
  Module6
  Module7
end
