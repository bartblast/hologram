defmodule Hologram.Entity.Metadata do
  @moduledoc false

  # The framework's own state on an entity struct, held under its __meta__ field: the write the
  # struct is carrying - the op on each attribute (a value put on it, or an amount to move it
  # by), the relationship edges to add or delete, and the authority claimed for it - which the
  # DB verbs read and apply, and, for a struct that was read, the revision each settable column
  # was last set at - what a write will say it was based on. Every entity struct carries one,
  # empty until a stage records into it or a read fills it, so a reader never guards against nil
  # and a clean struct always compares equal to another.
  #
  # A write authored elsewhere carries its writer's stamp too, which the executor stores as the
  # revision of every column the write sets, in place of one from this node's clock - the writer's
  # next write says it was based on that exact value, so nothing may re-author it on the way in.

  alias Hologram.Entity

  defstruct attribute_ops: %{}, claim: nil, relationship_ops: %{}, revisions: %{}, stamp: nil

  @type attribute_op :: {:put, any} | {:increment, integer}

  @type t :: %__MODULE__{
          attribute_ops: %{atom => attribute_op},
          claim: {:authorize, atom} | :trust | nil,
          relationship_ops: %{{atom, Entity.id()} => :add | :delete},
          revisions: %{atom => pos_integer},
          stamp: pos_integer | nil
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
            attribute_ops: metadata.attribute_ops,
            claim: metadata.claim,
            relationship_ops: metadata.relationship_ops,
            revisions: metadata.revisions,
            stamp: metadata.stamp
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
