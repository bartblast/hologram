defmodule Hologram.Query.RowField do
  @moduledoc false

  # Stands for a field of the row a derived field is computed for, inside its definition: an
  # attribute, a reference field or a path to an attribute of a related row. A derived field's
  # query compares the rows it reads with the row it belongs to, and that row has no value while
  # the definition is built - so a condition pinning one of its fields stores the name instead, as
  # a name of the row one level out.

  @enforce_keys [:name, :owner]

  defstruct [:name, :owner]

  @type t :: %__MODULE__{name: atom | list(atom), owner: module}
end
