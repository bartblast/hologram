defmodule Hologram.Test.Fixtures.Compiler.Processor.Module20 do
  use Hologram.Page

  def template do
    ~H"""
    <div class="test-class" id={Hologram.Test.Fixtures.Compiler.Processor.Module17.fun_1()}>
      test content
    </div>
    """
  end
end
