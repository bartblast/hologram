defmodule Hologram.Mutation.Write do
  @moduledoc false

  # One write of a batch, as the server holds it once the envelope has been parsed: the op, the
  # entity type module, the id of the row it acts on, and what the op carries - values keyed by
  # field and decoded to the terms the model declares, the revisions the writer saw, the claim it
  # makes, and the stamp its writer authored - or, for an edge, the relationship and the row at
  # the other end.
  #
  # Every field is already checked against THIS build's model by the time one of these exists, so
  # what reads it does not check again.

  defstruct based_on: %{},
            claim: nil,
            data: %{},
            entity_type: nil,
            id: nil,
            op: nil,
            relationship: nil,
            stamp: nil,
            target_id: nil

  @type t :: %__MODULE__{
          based_on: %{atom => pos_integer},
          claim: {:authorize, atom} | nil,
          data: %{atom => any},
          entity_type: module | nil,
          id: String.t() | nil,
          op: :create | :update | :delete | :add_relationship | :delete_relationship | nil,
          relationship: atom | nil,
          stamp: pos_integer | nil,
          target_id: String.t() | nil
        }
end
