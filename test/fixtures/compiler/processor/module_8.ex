defmodule Hologram.Test.Fixtures.Compiler.Processor.Module8 do
  use Hologram.Component

  def template do
    ~H"""
    <Hologram.Test.Fixtures.Compiler.Processor.Module6></Hologram.Test.Fixtures.Compiler.Processor.Module6>
    test_text
    <Hologram.Test.Fixtures.Compiler.Processor.Module7></Hologram.Test.Fixtures.Compiler.Processor.Module7>
    """
  end
end
