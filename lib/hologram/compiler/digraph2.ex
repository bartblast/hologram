defmodule Hologram.Compiler.Digraph2 do
  @moduledoc false

  alias Hologram.Compiler.Digraph2

  defstruct [:vertices, :edges, :reverse_edges]

  @type t :: %__MODULE__{
          vertices: %{any => boolean},
          edges: %{any => %{any => boolean}},
          reverse_edges: %{any => %{any => boolean}}
        }

  @type edge :: {vertex, vertex}
  @type vertex :: any

  def new do
    %Digraph2{vertices: %{}, edges: %{}, reverse_edges: %{}}
  end
end
