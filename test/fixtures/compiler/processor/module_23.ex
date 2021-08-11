defmodule Hologram.Test.Fixtures.Compiler.Processor.Module23 do
  use Hologram.Component

  def template do
    ~H"""
      <Hologram.Test.Fixtures.Compiler.Processor.Module21 />
    """
  end
end
