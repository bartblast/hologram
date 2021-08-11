defmodule Hologram.Test.Fixtures.Compiler.Processor.Module21 do
  use Hologram.Component

  def template do
    ~H"""
    <div class="test-class" id={Hologram.Test.Fixtures.Compiler.Processor.Module17.fun_1()}>
      test content
    </div>
    """
  end
end
