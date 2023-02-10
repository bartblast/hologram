defmodule Hologram.Compiler.ImportDirectiveTransformer do
  alias Hologram.Compiler.IR.ImportDirective

  def transform({:import, _, [{:__aliases__, _, alias_segs}, opts]}) do
    only = if opts[:only], do: opts[:only], else: []
    except = if opts[:except], do: opts[:except], else: []
    build_import(alias_segs, only, except)
  end

  def transform({:import, _, [{:__aliases__, _, alias_segs}]}) do
    build_import(alias_segs, [], [])
  end

  defp build_import(alias_segs, only, except) do
    %ImportDirective{alias_segs: alias_segs, only: only, except: except}
  end
end
