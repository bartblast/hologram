defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module28 do
  use Hologram.Component

  def template do
    ~H"""
    <div class="test-class" id={Hologram.Test.Fixtures.Compiler.Pruner.Module20.some_fun_2()}>
      test content
    </div>
    """
  end
end
