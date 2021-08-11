defmodule Hologram.Test.Fixtures.Compiler.Processor.Module19 do
  use Hologram.Component

  def template do
    ~H"""
    abc{Hologram.Test.Fixtures.Compiler.Processor.Module17.fun_1()}bcd
    """
  end
end
