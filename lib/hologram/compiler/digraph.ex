defmodule Hologram.Compiler.Digraph do
  @moduledoc false
  # A high-performance directed graph implementation optimized for large datasets
  # and concurrent access. Uses ETS tables for storage.

  # This implementation stores:
  # - Vertices in an ETS set
  # - Edges in an ETS bag (allows duplicate edges with same source)
  # - Reverse edges in another ETS bag for efficient inbound edges queries
end
