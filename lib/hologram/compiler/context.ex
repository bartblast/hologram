defmodule Hologram.Compiler.Context do
  defstruct module: nil, uses: [], imports: [], requires: [], aliases: [], attributes: [], block_bindings: []
end
