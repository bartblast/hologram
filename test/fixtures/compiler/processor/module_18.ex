defmodule Hologram.Test.Fixtures.Compiler.Processor.Module18 do
  use Hologram.Page

  def template do
    ~H"""
    abc{Hologram.Test.Fixtures.Compiler.Processor.Module17.fun_1()}bcd
    """
  end
end
