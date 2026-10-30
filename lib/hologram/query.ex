defmodule Hologram.Query do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Query.Expression
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage

  # A query term - what the stages build and the executors run. Each field is named for the stage
  # that sets it, with one exception: one/1 and count/1 set cardinality, since a term cannot be
  # both. A term records fields, not the order the stages were called in - filter appends,
  # sort replaces, include adds a key or merges into one - so two pipes reaching the same
  # fields are one query, which is what Hologram.Query.Registry.id/1 relies on. A term is always
  # about one entity type, so a struct written without one is refused at the literal.
  @enforce_keys [:entity]

  defstruct cardinality: :set,
            entity: nil,
            filter: [],
            include: %{},
            offset: nil,
            sort: [],
            take: nil,
            trust: false

  # Another attribute of the same row, or a path to an attribute of a related row, compared with
  # the predicate's attribute.
  @type attribute_operand :: {:attribute, atom | path}

  @type bound :: non_neg_integer | placeholder | nil

  @type cardinality :: :count | :one | :set

  @type clause :: predicate | disjunction

  # A disjunction holds when any of its alternatives does, and an alternative is a list of clauses
  # that all hold - so a disjunction nests inside an alternative the way it sits in a filter.
  @type disjunction :: {:or, list(list(clause))}

  @type operator :: :!= | :< | :<= | :== | :> | :>= | :in | :not_in

  @type ordering :: {atom | placeholder, :asc | :desc | placeholder}

  # Two or more names: the to-one relationships followed from the queried type, in order, and an
  # attribute of the row they lead to.
  @type path :: list(atom)

  @type placeholder :: {:placeholder, atom}

  # The data form a filter is given in: an attribute, a path or a placeholder paired with a value.
  @type predicates :: list({atom | path | Placeholder.t(), any})

  # The operand is a literal, a placeholder, the acting user ({:actor}) or an attribute_operand.
  @type predicate :: {atom | path | placeholder, operator, any}

  @type t :: %__MODULE__{
          cardinality: cardinality,
          entity: module,
          filter: list(clause),
          include: %{atom => t},
          offset: bound,
          sort: list(ordering),
          take: bound,
          trust: boolean
        }

  @doc """
  Records on the given entity struct that the given to-many relationship gains an edge to the
  entity with the given target id, and returns the struct - the edge is added when DB.update/1
  writes the struct.

  The entity is an entity struct - one a query read, or one Entity.new/2 constructed. The
  relationship is one of its declared to-many relationships, and the target id an entity id.
  The edge is recorded in the struct's metadata under the relationship and target - a later
  add_relationship/3 or delete_relationship/3 for the same edge replaces it, so a struct
  carries one operation per edge, the last one recorded. The relationship's own field is left as
  it is: what the struct holds of the relationship's rows is what the query read, and the
  recorded edge is not among them until it is written. Whether the target exists is the
  write's to judge.

  Raises ArgumentError when the entity is not an entity struct, when the target id is not a
  string, or when the relationship is a to-one relationship, an attribute, or unknown.
  """
  @spec add_relationship(Entity.t(), atom, Entity.id()) :: Entity.t()
  defdelegate add_relationship(entity, relationship_name, target_id), to: Stage

  @doc """
  Claims the acting user's authority for the given operation on the given entity struct and
  returns the struct - the DB verb writing it evaluates that operation, against the row, for
  the acting user, instead of the operation the verb performs on its own.

  The entity is an entity struct - one a query read, or one Entity.new/2 constructed. The
  operation is an atom naming an entity operation the entity type declares an allow line for -
  `:pin`, `:publish`, `:archive` - and is recorded in the struct's metadata as the claim the
  write carries. There is no user argument: the subject of a claim is always the acting user.
  A write carries exactly one claim - a struct already claiming an authority, through
  authorize/2 or trust/1, cannot claim another.

  Raises ArgumentError when the entity is not an entity struct, when the operation is not an
  atom, when the operation is neither a framework operation nor one an allow line on the entity
  type names (see Hologram.Policy.validate_operation!/2), or when the struct already carries a
  claim.
  """
  @spec authorize(Entity.t(), atom) :: Entity.t()
  defdelegate authorize(entity, operation), to: Stage

  @doc """
  Marks the given query as counting and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. A counting query evaluates to a non-negative integer - the number of
  results the query otherwise evaluates to, view bounds included.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, or when a cardinality is already marked.
  """
  @spec count(module | t) :: t
  defdelegate count(query), to: Stage

  @doc """
  Records on the given entity struct that the given integer attribute is to move DOWN by the
  given amount, and returns the struct - the attribute is moved when DB.update/1 writes the
  struct. increment/3 with the opposite sign and one stricter rule: the amount is a positive
  integer, since a literal move down is what this spelling is for - a computed amount of either
  sign goes through increment/3. Otherwise the same arguments, the same recording and the same
  rules - see increment/3.
  """
  @spec decrement(Entity.t(), atom, pos_integer) :: Entity.t()
  defdelegate decrement(entity, name, amount), to: Stage

  @doc """
  Records on the given entity struct that the given to-many relationship loses its edge to the
  entity with the given target id, and returns the struct - the edge is deleted when
  DB.update/1 writes the struct. add_relationship/3 with the opposite operation: the same
  arguments, the same recording, the same replacement of an earlier operation on the edge,
  and deleting an edge the relationship does not hold is a no-op at the write.

  Raises ArgumentError when the entity is not an entity struct, when the target id is not a
  string, or when the relationship is a to-one relationship, an attribute, or unknown.
  """
  @spec delete_relationship(Entity.t(), atom, Entity.id()) :: Entity.t()
  defdelegate delete_relationship(entity, relationship_name, target_id), to: Stage

  @doc """
  Appends predicates to the given query's filter list and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built query
  term. The predicates are an Elixir expression in which a bare name is an attribute of the
  queried entity - declared, system, or a to-one reference field (`<relationship name>_id`) - a
  dotted name is a path through to-one relationships to an attribute of the row at its end
  (`project.archived`, `project.owner.email`), and anything from the surrounding code is pinned
  with `^`. A literal - an atom (`nil`, `true` and `false` included), a number, a string or a
  module name - needs no pin, and any other value is pinned: a sigil, a list held in a variable, a
  struct, a call.

      Task
      |> filter(project_id: ^project_id, status: :todo)
      |> filter(priority >= 3 and created_at < ^cutoff)
      |> filter(status in [:todo, :doing])
      |> filter(archived_at == nil)
      |> filter(owner_id == ^owner_id or shared == true)
      |> filter(due_on < starts_on)
      |> filter(project.archived == false and project.owner.email == ^email)

  The predicates are one of:

    * a keyword list of equalities whose values are literals or pinned - `project_id: ^id` -
      where a value is always an equality operand: a comparison, a membership or a range is
      written as an expression, so `priority: {:>=, 3}` is refused in favour of `priority >= 3`
    * a comparison of an attribute or a path with a literal, a pinned value, another attribute of
      the same row or a path - `==`, `!=`, `<`, `<=`, `>`, `>=` - `due_on < starts_on`,
      `due_on <= project.ends_on`
    * a membership - `status in [:todo, :doing]`, `priority in 3..5`, `status in ^statuses`,
      `status not in [:done]`
    * comparisons and memberships joined with `and`
    * alternatives joined with `or` - `owner_id == ^owner_id or shared == true` - where `and`
      binds tighter than `or` and parentheses group, as Elixir reads them: `a and b or c` is
      `(a and b) or c`
    * a pinned list of predicates for a filter built at runtime - `filter(^predicates)`, where
      the list holds attribute names paired with values, operator tuples (`{:>=, 3}`,
      `{:in, list}`, `{:not_in, list}`), membership lists, lists of operator tuples applying
      all of them (`[{:>=, monday}, {:<, next_monday}]`), integer ranges or
      `{:attribute, name}` tuples naming another attribute of the row, bare or as the operand of
      a comparison operator (`[due_on: {:<, {:attribute, :starts_on}}]`), where a path is the
      list of its names, as a key or inside an attribute tuple (`[{[:project, :archived], false}]`),
      and where an `or:` entry holding two or more predicate lists is a disjunction, any one of
      which has to hold (`[status: :todo, or: [[owner_id: id], [shared: true]]]`)

  Each predicate becomes one or more `{attribute, operator, value}` triples, and a disjunction
  one `{:or, alternatives}` clause, appended in the given order. A query term is a Hologram.Query
  struct - a plain-data description of a query, so building it never executes anything.

  Nil is a regular value for `==`, `!=` and membership: `status != :done` also matches a row with
  no status, `status in [nil, :done]` reads "done or unset", and a negated membership without nil
  matches missing values. Nil keeps its meaning inside a disjunction:
  `priority > 3 or shared == true` matches a shared row with no priority, since the comparison
  passes over nil and the other alternative holds.

  A path reads the row its relationships lead to, and is checked by the attribute it ends at - its
  type, its values, its order. A path that leads nowhere reads as nil: through an empty
  relationship, a reference to a row that is gone, or a row the reading session may not read, which
  an include of it embeds as nil too. Nil keeps its meaning there, so `project.archived != true`
  matches a task with no project, and `project.archived == nil` finds it. A condition that wants the
  related row to be there says so: `project.id != nil and project.archived != true` - `project.id`
  reads nil exactly when there is no project the session may read, where `project_id != nil` asks
  only whether the reference is set. Paths go through any number of to-one relationships, and the
  rows along a path are downloaded and kept current with the query, whether or not it includes
  them.

  Two attributes compare when they have the same type, or when one widens to the other - an
  integer to a float, compared as floats. Two enums compare when they declare the same values in
  the same order, and an attribute never compares with itself. Nil keeps its meaning: `owner_id ==
  assignee_id` matches a row with neither set, `owner_id != assignee_id` one with only one of them
  set, and an ordering comparison matches no row with either side missing. Two strings compare
  through their sort keys, as a string does against a literal, and `==` stays exact.

  Ordering comparisons require an orderable attribute - every type but boolean and uuid - and a
  non-nil operand - SQL comparisons with NULL never match, so a nil operand would mean different
  things on the two execution tiers. A comparison on an enum attribute reads the declared
  `values:` order, so `priority >= :medium` on `[:low, :medium, :high]` means medium or high, and
  the operand must be one of the declared values. A comparison on a string attribute reads the
  order `sort` puts it in - case and diacritics fold the way they do in the list - and a
  bound names a position in that list, spelled the way the list spells it: `name >= "M"` reaches
  `M`, `m`, `Mango`, while `name >= "m"` starts at `m`.

  An integer range (`priority in 3..10`) is shorthand for the inclusive bounds - it expands into
  a `>=` triple and a `<=` triple. Ranges require an integer attribute, step 1, and at least one
  element. Membership lists must not be empty.

  To-one reference fields take equality and membership, while ordering
  comparisons and ranges reject them like any other non-orderable type. To-many relationships
  have no reference field, and neither relationship name itself is filterable - a path names the
  related row's attributes instead.

  Raises Hologram.CompileError, naming the location, when a keyword list or a pinned list stands
  as one side of `and` or `or`, or when the predicates take any other form - a bare name where
  only a value goes (a keyword value, a membership element, a range bound) is most likely a
  forgotten pin, and the error says so. Raises ArgumentError when the query is neither an entity
  type module nor a query term, when pinned predicates are not a list of name and value pairs - a
  name being an attribute or a path - when a predicate names a relationship or an unknown attribute
  - on the right side of a comparison, which is how a forgotten pin on a variable reads - when a
  path goes through a to-many relationship, an attribute or an unknown relationship, or ends at a
  name the related type does not declare, when a disjunction holds fewer than two predicate lists
  or one of them is empty or not such a list, when a comparison names an attribute with itself or
  two attributes that do not compare, or when a value is invalid for its attribute or its operator
  - a pinned keyword value holding a list, a tuple or a range is refused as an equality operand,
  since membership and comparisons are written as expressions.
  """
  defmacro filter(query, predicates) do
    lowered = Expression.predicates(predicates, __CALLER__)

    quote do
      Stage.filter(unquote(query), unquote(lowered))
    end
  end

  @doc """
  Adds relationship traversals to the given query's include map and returns the
  resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. Relationships must be declared on the query's entity type - the whole
  related entity (to-one) or entity set (to-many) is embedded in results under the
  relationship's name.

  A relationship is named with a bare name, and a nested one with a path through the
  relationships it traverses. Several go in a list, where entries sharing a first relationship
  merge, and a keyword entry pairs a relationship with a sub-builder:

      Project |> include(owner)
      Project |> include(tasks.owner)
      Project |> include([owner, tasks.owner, tasks.project])
      Project |> include([owner, tasks: &open_tasks/1])

  A sub-builder is a one-argument function receiving the related entity's base query term
  and returning a refined query term for the same entity - to-many includes take nested
  clauses this way. It is written in place (`fn` or a capture) or pinned. `include/3` passes
  one for a relationship or a path directly - `include(project.tasks, &open_tasks/1)`. A
  relationship or a whole spec chosen at runtime is pinned - `include(^relationship)` - and a
  pinned spec is the data form: names, `{name, nested_spec}` pairs and `{name, sub_builder}`
  pairs.

  To-one includes take no clauses (a single embedded entity has nothing to filter,
  order, or slice) - nested includes are their only refinement. Includes nest to any depth.

  Including a relationship that is already included merges the two when neither narrows
  it with clauses: what each includes is included, by the same rule at every level, so
  `query |> include(project.owner) |> include(project.tasks)` includes the project with
  both.

  Raises Hologram.CompileError, naming the location, when a relationship is written as an atom
  (`include(:owner)` is refused in favour of `include(owner)`), when a keyword entry nests a
  relationship rather than a sub-builder (`include(tasks: owner)` is refused in favour of
  `include(tasks.owner)`), or when a spec, an entry or a sub-builder is anything else. Raises
  ArgumentError when the query is neither an entity type module nor a query term, when a
  spec is invalid or empty, when a name is not a declared relationship - which is how a
  forgotten pin on a variable reads - when a relationship is included again and either include
  carries clauses, when a sub-builder is not a one-argument function or does not return a query
  term for the related entity type, or when a to-one include carries clauses.
  """
  defmacro include(query, spec) do
    lowered = Expression.inclusion(spec, __CALLER__)

    quote do
      Stage.include(unquote(query), unquote(lowered))
    end
  end

  @doc """
  Adds the traversal of the given relationship or path, refined by the given sub-builder at its
  end, to the given query's include map and returns the resulting query term - see include/2.
  """
  defmacro include(query, relationship, sub_builder) do
    hops = Expression.relationship(relationship, __CALLER__)
    lowered_sub_builder = Expression.sub_builder(sub_builder, __CALLER__)

    nested_include(query, hops, lowered_sub_builder)
  end

  @doc """
  Records on the given entity struct that the given integer attribute is to move UP by the given
  amount, and returns the struct - the attribute is moved when DB.update/1 writes the struct.

  The entity is an entity struct - one a query read, or one Entity.new/2 constructed. The name is
  a counter - a declared attribute of type :integer that is not optional, so it always holds a
  number - and the amount any integer: a negative one moves the attribute down, which is how a
  computed amount passes through with its sign, and decrement/3 is the readable spelling for a
  literal move down. The amount is recorded in the struct's metadata as an increment op under
  the attribute's name (decrement/3 records a negative one), and several increments and
  decrements of one attribute add up, so a sum that reaches zero leaves nothing recorded. The
  struct's own field moves with it, so a caller reads back the value it asked for - a preview:
  what the attribute ends up holding is the row's to compute at the write, from whatever value it
  holds then, which is what lets two writers moving one attribute add up instead of one
  overwriting the other. Only the recorded amount is written, never the field. The attribute's
  constraints are judged on that result at the write, so a move that would cross a declared
  minimum, maximum or range is reported by DB.update/1.

  Stages apply in order and the struct holds one op per attribute: moving an attribute the
  struct already carries a put value for folds the amount into that value (put 10 then
  increment 1 records a put of 11), and putting an attribute the struct carries an increment for
  replaces the increment.

  Raises ArgumentError when the entity is not an entity struct, when the amount is not an
  integer, when the name is an optional integer attribute, a non-integer attribute, a
  relationship, a system attribute, or unknown, when the put value the amount would fold into
  is not an integer, or when the struct's field holds nil - a counter always holds a number,
  and a struct that has none has nothing to move.
  """
  @spec increment(Entity.t(), atom, integer) :: Entity.t()
  defdelegate increment(entity, name, amount), to: Stage

  @doc """
  Sets the given query's limit - the maximum number of results the query evaluates
  to - and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The limit is a non-negative integer, written as a literal or pinned when it
  comes from the surrounding code - `limit(20)`, `limit(^page_size)`. It bounds what the query
  evaluates to, not the underlying data. A later call replaces a limit an earlier one set.

  Raises Hologram.CompileError, naming the location, when the limit is neither an integer
  literal nor pinned. Raises ArgumentError when the query is neither an entity type module nor a
  query term, or when the limit is not a non-negative integer.
  """
  defmacro limit(query, value) do
    lowered = Expression.bound(value, :limit, __CALLER__)

    quote do
      Stage.take(unquote(query), unquote(lowered))
    end
  end

  @doc """
  Sets the given query's offset - the number of results skipped before the query's
  results begin - and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The offset is a non-negative integer, written as a literal or pinned when it
  comes from the surrounding code - `offset(40)`, `offset(^skip)`. It slices what the query
  evaluates to, not the underlying data. A later call replaces an offset an earlier one set.

  Raises Hologram.CompileError, naming the location, when the offset is neither an integer
  literal nor pinned. Raises ArgumentError when the query is neither an entity type module nor a
  query term, or when the offset is not a non-negative integer.
  """
  defmacro offset(query, value) do
    lowered = Expression.bound(value, :offset, __CALLER__)

    quote do
      Stage.offset(unquote(query), unquote(lowered))
    end
  end

  @doc """
  Marks the given query as single-result and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. A single-result query evaluates to the first entity under the query's
  total order, or nil when no entity matches - never an error on multiplicity, since
  live re-evaluation makes transient multiplicity a normal state.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, or when a cardinality is already marked.
  """
  @spec one(module | t) :: t
  defdelegate one(query), to: Stage

  @doc """
  Sets the given query's view bounds to the requested page and returns the resulting
  query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. Options are `page:` (a positive integer, 1-based) and `size:` (a positive
  integer, the number of results per page), both required, each written as a literal or pinned
  when it comes from the surrounding code - `paginate(page: ^page, size: 25)` - or the whole
  options pinned. Pagination expands into the offset and limit view bounds -
  `paginate(page: 2, size: 20)` sets offset 20 and limit 20 - and slices what the query
  evaluates to, not the underlying data, replacing view bounds already set.

  Raises Hologram.CompileError, naming the location, when an option value is neither an
  integer literal nor pinned, or when the options are neither a keyword list nor pinned. Raises
  ArgumentError when the query is neither an entity type module nor a query term, when the
  options are not a keyword list holding exactly :page and :size, or when either option is not
  a positive integer.
  """
  defmacro paginate(query, opts) do
    lowered = Expression.pagination(opts, __CALLER__)

    quote do
      Stage.paginate(unquote(query), unquote(lowered))
    end
  end

  @doc """
  Puts the given attribute values on the given entity struct and returns it, with the values
  recorded as the changes DB.update/1 writes.

  The entity is an entity struct - one a query read, or one Entity.new/2 constructed. Values
  are a keyword list or a map keyed by declared attribute names and to-one reference fields
  (`<relationship name>_id`) - what DB.update/3 takes as changes. Each value is set on the
  struct's field and recorded under the same name in the struct's metadata, so a later put of
  the same name replaces the earlier one, and replaces an increment recorded for it by
  increment/3 or decrement/3 - stages apply in order, and the struct holds one op per attribute.
  Values are judged at the write, not here - a value
  the declarations refuse is reported by DB.update/1, and a struct holding one reads like any
  other until then.

  Only a put value is written: a field changed any other way - `%{entity | name: value}` - is
  neither recorded nor written, and an entity carrying no recorded change is refused by
  DB.update/1.

  Raises ArgumentError when the entity is not an entity struct, when the values are neither a
  keyword list nor a map, or when a name is a relationship, a system attribute, or unknown.
  """
  @spec put_attribute(Entity.t(), keyword | map) :: Entity.t()
  defdelegate put_attribute(entity, values), to: Stage

  @doc """
  Puts the given attribute value on the given entity struct and returns it, with the value
  recorded as a change DB.update/1 writes - put_attribute/2 for one name and value.
  """
  @spec put_attribute(Entity.t(), atom, any) :: Entity.t()
  defdelegate put_attribute(entity, name, value), to: Stage

  @doc """
  Sets the given query's sort order and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The spec is an attribute named with a bare name (ascending), or a list of
  attributes and `{attribute, :asc | :desc}` pairs - keyword syntax reads naturally:

      Task |> sort(priority)
      Task |> sort([priority, title])
      Task |> sort(priority: :desc, title: :asc)

  An attribute chosen at runtime is pinned, as is a direction or a whole spec -
  `sort(^sort_field)`, `sort(title: ^direction)`, `sort(^[{sort_by, sort_dir}])`.
  Each entry becomes an `{attribute, direction}` pair, in the given order.

  A later call replaces the order an earlier one set rather than adding to it, so
  `Task |> sort(title) |> sort(priority)` sorts by priority alone. Two `Enum.sort_by` calls in
  a row work the other way: the sort is stable, so the first one survives as the tiebreaker. A
  query names its secondary key in the same call, after the first - `sort([priority, title])`.
  Precedence is positional, so an order states itself in one place or not at all.

  An enum attribute sorts by the position of its values in the declared `values:` list -
  `[:low, :medium, :high]` sorts low, medium, high, on both execution tiers.

  Raises Hologram.CompileError, naming the location, when an attribute is written as an atom
  (`sort(:priority)` is refused in favour of `sort(priority)`), when a direction is
  neither an atom nor pinned, or when the spec or an entry is neither a bare name, a pair nor
  pinned. Raises ArgumentError when the query is neither an entity type module nor a query term,
  when the spec is neither an attribute name nor a list, when an entry names a relationship or an
  unknown attribute - which is how a forgotten pin on a variable reads - or when a direction is
  neither :asc nor :desc.
  """
  defmacro sort(query, spec) do
    lowered = Expression.ordering(spec, __CALLER__)

    quote do
      Stage.sort(unquote(query), unquote(lowered))
    end
  end

  @doc """
  Claims the server's own authority for the given entity struct and returns the struct - the
  DB verb writing it evaluates no policy, and applies the write as trusted code would.

  The entity is an entity struct - one a query read, or one Entity.new/2 constructed. The
  claim is recorded in the struct's metadata, and is the spelling for a write no user's
  authority is behind: recording what an external system reported, applying what a poller
  fetched. Trust claims authority, it does not skip validation - a trusted write is validated,
  stamped and recorded like any other, and creator roles are granted when an acting user is
  set. A write carries exactly one claim - a struct already claiming an authority, through
  authorize/2 or trust/1, cannot claim another.

  On a query - an entity type module or a query term - it marks the query as read on the
  server's own authority: DB.read/1 reads it raw whether or not a user is acting. The spelling
  for a read that must see past the acting user's policies, such as finding the user an invite
  names by email when users may read only themselves. A registered query (a component's
  from_query) cannot carry it - the build refuses one that does - since a component's query is
  read for the session user on both tiers.

  Raises ArgumentError when the subject is neither an entity struct, an entity type module nor
  a query term, or when a struct already carries a claim.
  """
  @spec trust(Entity.t() | module | t) :: Entity.t() | t
  defdelegate trust(subject), to: Stage

  # A path with a sub-builder includes each hop through a sub-builder that includes the next, the
  # given one refining the last: project.tasks with a builder includes project with
  # fn related -> include(related, :tasks, builder) end. Every hop goes through include/3, so a
  # path refuses a sub-builder that is not a function in the words a single relationship does.
  defp nested_include(query, [name], sub_builder) do
    quote do
      Stage.include(unquote(query), unquote(name), unquote(sub_builder))
    end
  end

  defp nested_include(query, [name | rest], sub_builder) do
    related = Macro.var(:related, __MODULE__)
    inner = nested_include(related, rest, sub_builder)

    quote do
      Stage.include(unquote(query), unquote(name), fn unquote(related) -> unquote(inner) end)
    end
  end

  # Rendered as the struct with the fields at their default left out - a fresh term shows its
  # entity type alone, and an include shows as the nested struct it holds. Still the literal that
  # rebuilds the term exactly (an omitted field takes its default, and entity is never omitted),
  # and the spelling the tests assert with, so what inspect prints is what a reader writes. Bare,
  # five of the eight fields are at their default on every term and every sub-term, and the
  # signal drowns.
  defimpl Inspect do
    import Inspect.Algebra

    @impl Inspect
    def inspect(term, opts) do
      defaults =
        Hologram.Query
        |> struct()
        |> Map.from_struct()

      fields =
        Enum.reject(
          [
            cardinality: term.cardinality,
            entity: term.entity,
            filter: term.filter,
            include: term.include,
            offset: term.offset,
            sort: term.sort,
            take: term.take,
            trust: term.trust
          ],
          fn {name, value} -> value == Map.fetch!(defaults, name) end
        )

      container_doc("%Hologram.Query{", fields, "}", opts, &field_doc/2, separator: ",")
    end

    defp field_doc({name, value}, opts) do
      concat([Atom.to_string(name), ": ", to_doc(value, opts)])
    end
  end
end
