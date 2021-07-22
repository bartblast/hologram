defmodule Hologram.Test.Fixtures.Compiler.Processor.Module12 do
  use Hologram.Page

  def template do
    ~H"""
    <div></div>
    test_text
    {@value}
    """
  end
end
