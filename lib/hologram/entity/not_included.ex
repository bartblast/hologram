defmodule Hologram.Entity.NotIncluded do
  @moduledoc """
  The value of an entity field that wasn't loaded, such as one the query which read the entity
  didn't include.

  A relationship (to-one, to-many or inverse) or a derived field holds `%NotIncluded{}` until a
  query includes it, on the server and in the browser alike. Once included, a to-one relationship
  holds `nil` or the related entity, a to-many relationship holds a list of entities, and a
  derived field holds its value. Add the field to the query's `include` to read it.

  An entity no query read holds it too, like one built with `new/1` or one a create returns. To
  read such a field, read the entity through a query that includes it.

  Tell a placeholder from a value with `Hologram.Entity.included?/1`, which pages and components
  import, or by matching on the struct alone. The struct's `__meta__` key is internal and may
  change, so don't read it or match on it.

  ## Examples

  In a template:

      {%if !included?(@todo.project)}
        <p>Project not loaded</p>
      {/if}

  Matching on the struct works too, in server or browser code:

      alias Hologram.Entity.NotIncluded

      case todo.project do
        %NotIncluded{} -> :not_loaded
        nil -> :no_project
        project -> project.name
      end

  Or in a template:

      {%if match?(%NotIncluded{}, @todo.project)}
        <p>Project not loaded</p>
      {/if}
  """

  # The default value of an entity struct's relationship embed and to-many fields, and of its
  # derived fields. The internal __meta__ map names the field the placeholder stands in for, as
  # %{field: name}.

  defstruct __meta__: %{}

  @typedoc """
  A field the query didn't include. Match on the struct alone, `__meta__` is internal.
  """
  @type t :: %__MODULE__{__meta__: map}
end
