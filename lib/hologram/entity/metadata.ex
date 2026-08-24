defmodule Hologram.Entity.Metadata do
  @moduledoc false

  # The framework's own state on an entity struct, held under its __meta__ field: the write the
  # struct is carrying - the attribute values put on it, the relationship edges to add or delete,
  # and the authority claimed for it - which the DB verbs read and apply. Every entity struct
  # carries one, empty until a stage records into it, so a reader never guards against nil and a
  # clean struct always compares equal to another.

  defstruct attribute_changes: %{}, claim: nil, relationship_ops: %{}

  @type t :: %__MODULE__{
          attribute_changes: %{atom => any},
          claim: {:authorize, atom} | :trust | nil,
          relationship_ops: %{{atom, String.t()} => :add | :delete}
        }

  # Rendered as what is recorded and nothing else - a clean struct shows an empty pair of
  # brackets, and a field at its default is left out. Bare, the struct wraps to four lines inside
  # every entity struct's inspect and every KeyError naming one, with three of them saying
  # "nothing".
  defimpl Inspect do
    import Inspect.Algebra

    @impl Inspect
    def inspect(metadata, opts) do
      fields =
        Enum.reject(
          [
            attribute_changes: metadata.attribute_changes,
            claim: metadata.claim,
            relationship_ops: metadata.relationship_ops
          ],
          fn {_name, value} -> value in [%{}, nil] end
        )

      container_doc("#Hologram.Entity.Metadata<", fields, ">", opts, &field_doc/2, separator: ",")
    end

    defp field_doc({name, value}, opts) do
      concat([Atom.to_string(name), ": ", to_doc(value, opts)])
    end
  end
end
