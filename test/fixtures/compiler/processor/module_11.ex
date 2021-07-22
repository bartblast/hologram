defmodule Hologram.Test.Fixtures.Compiler.Processor.Module11 do
  use Hologram.Component

  def template do
    ~H"""
    <div></div>
    test_text
    {@value}
    """
  end
end
