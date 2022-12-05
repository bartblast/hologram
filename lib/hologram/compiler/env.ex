defmodule Hologram.Compiler.Env do
  def init do
    %{__ENV__ | context_modules: [], file: nil, function: nil, line: nil, module: nil}
  end
end
