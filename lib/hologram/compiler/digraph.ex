defmodule Hologram.Compiler.Digraph do
  @moduledoc false
  # A high-performance directed graph implementation optimized for large datasets
  # and concurrent access. Uses ETS tables for storage.

  # This implementation stores:
  # - Vertices in an ETS set
  # - Edges in an ETS bag (allows duplicate edges with same source)
  # - Reverse edges in another ETS bag for efficient inbound edges queries

  defstruct [:vertices_table, :edges_table, :reverse_edges_table]

  @type t :: %__MODULE__{
          vertices_table: :ets.tid(),
          edges_table: :ets.tid(),
          reverse_edges_table: :ets.tid()
        }

  @doc """
  Creates a new directed graph.
  """
  @spec new :: t
  def new do
    vertices_table = :ets.new(:vertices, [:set, :public, {:read_concurrency, true}])
    edges_table = :ets.new(:edges, [:bag, :public, {:read_concurrency, true}])
    reverse_edges_table = :ets.new(:reverse_edges, [:bag, :public, {:read_concurrency, true}])

    %__MODULE__{
      vertices_table: vertices_table,
      edges_table: edges_table,
      reverse_edges_table: reverse_edges_table
    }
  end
end
