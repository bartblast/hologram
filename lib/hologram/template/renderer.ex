defmodule Hologram.Template.Renderer do
  @moduledoc false

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.StringUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.Encoder
  alias Hologram.Component
  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.Server
  alias Hologram.Sync.Carry
  alias Hologram.Template.DOM
  alias Hologram.Template.Helpers

  # Every placeholder the mount script carries, whoever fills it in - the renderer answers for
  # most, the controller for the rest.
  @js_placeholder_pattern ~r/\$[A-Z_]+_JS_PLACEHOLDER/

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  # The characters a value cannot carry into a script element as the text of a JavaScript string
  # literal, each with the escape sequence it is written as instead. Every sequence is valid
  # inside all three kinds of literal - double-quoted, single-quoted and template - and reads back
  # as the character it stands for, so the value arrives unchanged whichever quotes the template
  # wrote around it.
  #
  #   \\   would eat the character after it
  #   "    '    `    would close the literal
  #   $    would open an expression inside a template literal
  #   \n   and \r are not allowed inside a literal at all
  #   NUL  is rewritten to U+FFFD by the HTML parser inside script data
  #   <    so that "</script" can never form in a page's inline script
  #
  # Hologram.Compiler.Encoder escapes a shorter set for the same reason: it writes the quotes
  # around its literal itself, so only one kind of quote can close it and "$" opens nothing. Here
  # the template author writes the quotes, so every kind has to be covered.
  #
  # WARNING: must match SCRIPT_TEXT_ESCAPES in the client renderer (renderer.mjs). The text the
  # two sides put inside a script element has to be identical, or the boot patch rebuilds the
  # element instead of adopting it, and the script runs twice.
  @script_text_escapes %{
    "\\" => "\\\\",
    "\"" => "\\\"",
    "'" => "\\'",
    "`" => "\\`",
    "$" => "\\$",
    "\n" => "\\n",
    "\r" => "\\r",
    <<0>> => "\\u{0}",
    "<" => "\\u{3C}"
  }

  @script_text_escapable_chars Map.keys(@script_text_escapes)

  @typedoc """
  A node of an evaluated tree: only what a document can hold - elements, text, comments, and the
  doctype. Text and attribute values are unescaped, and each attribute value is a single string
  (an empty value list is a boolean attribute).
  """
  @type tree_node ::
          {:doctype, String.t()}
          | {:element, String.t(), [{String.t(), [] | [text: String.t()]}], [tree_node]}
          | {:public_comment, [tree_node]}
          | {:text, String.t()}

  @typedoc """
  A rendered template as data: expressions evaluated, components flattened into the nodes their
  templates render, and slots expanded. `nil` is the tree of a tag that renders no node at all.

  For how this vocabulary is put on the wire for a client-side navigation, and the alternatives it
  was measured against, see: docs/navigation_payload_wire_format.md
  """
  @type tree :: tree_node | [tree_node] | nil

  defmodule Env do
    @moduledoc false

    defstruct context: %{},
              node_type: nil,
              parent_module: nil,
              slots: [],
              slots_parent_module: nil,
              tag_name: nil

    @type t :: %__MODULE__{
            context: %{(atom | {any, atom}) => any},
            node_type: :attribute | :element | :property | :public_comment | nil,
            parent_module: module | nil,
            slots: keyword(DOM.t()),
            slots_parent_module: module | nil,
            tag_name: String.t() | nil
          }
  end

  # TODO: revisit this shape when the vdom renderer and the template format are rewritten. It was
  # chosen for a client that rebuilds boxed terms from it; a client that walks plain JavaScript
  # literals wants a different one, and the object-attribute forms ruled out here become eligible
  # once the consumer collapses attributes by name anyway.
  # See: docs/navigation_payload_wire_format.md
  @doc """
  Encodes an evaluated tree as a JSON-encodable term, for a client that renders the page itself.

  The tree is a render the server already performed: it holds only elements, text, comments and
  the doctype, with every expression resolved. That is a closed vocabulary with no Elixir
  semantics in it, so it needs neither `Hologram.Compiler.Encoder` nor the boxed terms that
  encoder produces - a nested array says the same thing, and the client gets it already parsed
  out of the response body.

  A node's shape is what tells the client what it is, so nothing carries a constructor name it
  does not need. An element is `[tag_name, attributes, children]` and is the only node of length
  three. Attributes are one flat run of alternating names and values, with `nil` for an attribute
  that has no value. Text is a bare string. A comment is `["c", children]` and a doctype
  `["d", content]`, both of length two.

  Unlike `print_dom/1` this is not a markup projection, so nothing is escaped and nothing is
  dropped: `$key` travels, because it is what carries element identity across a navigation, and a
  void element keeps the children the tree gave it.

  The result is always a list, even for a single node or for a tag that rendered nothing, so the
  client never has to tell a node apart from a list of them.

  For why this shape and not one of the other 111 measured, see:
  docs/navigation_payload_wire_format.md

  ## Examples

      iex> tree = {:element, "div", [{"class", [text: "big"]}], [{:text, "Hologram"}]}
      iex> encode_tree(tree)
      [["div", ["class", "big"], ["Hologram"]]]
  """
  @spec encode_tree(tree) :: [term]
  def encode_tree(tree) do
    tree
    |> List.wrap()
    |> Enum.map(&encode_node/1)
  end

  @doc """
  Substitutes the given placeholders with the JavaScript source each maps to, in one pass over
  the given text.

  ONE pass, so nothing a replacement carries is read as a placeholder in turn - a value holding
  the text of another token would otherwise have that token honoured inside it, and these values
  hold whatever a URL, a database or a component's state put there.

  What an inserted value carries is neutralized for the same reason one stage further out: a
  token inside it survives this pass untouched and would be substituted by whoever interpolates
  next. Inserted values are JavaScript source or JSON, and in both a token can only sit inside a
  string, where spelling its `$` as an escape leaves the string saying exactly what it said.

  A token the map does not answer for is left as it was, for whoever answers for it later.
  """
  @spec interpolate_js(String.t(), %{String.t() => String.t()}) :: String.t()
  def interpolate_js(text, replacements) do
    Regex.replace(@js_placeholder_pattern, text, fn token ->
      case Map.fetch(replacements, token) do
        {:ok, js} -> neutralize_js_placeholders(js)
        :error -> token
      end
    end)
  end

  @doc """
  Substitutes the given placeholders with the JavaScript source each maps to, inside every
  script element's text across the given tree.
  """
  @spec interpolate_js_in_tree(tree, %{String.t() => String.t()}) :: tree
  def interpolate_js_in_tree(tree, replacements)

  def interpolate_js_in_tree({:element, "script", attributes, children}, replacements) do
    interpolated_children =
      Enum.map(children, fn
        {:text, text} -> {:text, interpolate_js(text, replacements)}
        child -> interpolate_js_in_tree(child, replacements)
      end)

    {:element, "script", attributes, interpolated_children}
  end

  def interpolate_js_in_tree({:element, tag_name, attributes, children}, replacements) do
    {:element, tag_name, attributes, interpolate_js_in_tree(children, replacements)}
  end

  def interpolate_js_in_tree(nodes, replacements) when is_list(nodes) do
    Enum.map(nodes, &interpolate_js_in_tree(&1, replacements))
  end

  def interpolate_js_in_tree(node, _replacements), do: node

  @doc """
  Maps the mount data to the placeholder each of its values answers for.

  The renderer names the mount data for the payload, where a field name is what the client reads.
  The document path needs the same values under the tokens the page's scripts carry, and the token
  vocabulary is this module's, since this is what leaves them in the tree.
  """
  @spec mount_replacements(%{atom => String.t()}) :: %{String.t() => String.t()}
  def mount_replacements(mount_data) do
    %{
      "$ACTOR_USER_ID_JS_PLACEHOLDER" => mount_data.actor_user_id,
      "$ASSET_MANIFEST_JS_PLACEHOLDER" => mount_data.asset_manifest,
      "$COMPONENT_REGISTRY_JS_PLACEHOLDER" => mount_data.component_registry,
      "$PAGE_MODULE_JS_PLACEHOLDER" => mount_data.page_module,
      "$PAGE_PARAMS_JS_PLACEHOLDER" => mount_data.page_params,
      "$SYNC_COUNTS_JS_PLACEHOLDER" => mount_data.sync_counts,
      "$SYNC_ROWS_JS_PLACEHOLDER" => mount_data.sync_rows
    }
  end

  @doc """
  Prints an evaluated DOM as HTML.

  An evaluated DOM holds text verbatim and each attribute value as a single string, both
  unescaped, so escaping belongs here: text is entity-encoded everywhere except inside a script
  element, whose body is code rather than markup.

  The `$`-prefixed attributes name what the framework reads rather than what the markup carries -
  event bindings and element keys among them - so they are left out. An attribute with an empty
  value prints as a bare name, and a void element prints without children.

  ## Examples

      iex> dom = {:element, "div", [{"class", [text: "big"]}], [{:text, "Hologram"}]}
      iex> print_dom(dom)
      ~s(<div class="big">Hologram</div>)
  """
  @spec print_dom(tree) :: String.t()
  def print_dom(tree) do
    print_node(tree, nil)
  end

  @doc """
  Renders the given DOM.

  ## Examples

      iex> dom = {:component, MyModule, [{"cid", [text: "my_component"]}], []}
      iex> render_dom(dom, %Env{}, %Server{})
      {
        "<div>state_a = 1, state_b = 2</div>",
        %{"my_component" => %{module: MyModule, struct: %Component{state: %{a: 1, b: 2}}}},
        %Server{session: %{user_id: 123}}
      }
  """
  @spec render_dom(DOM.t(), Env.t(), Server.t()) ::
          {String.t(), %{String.t() => %{module: module, struct: Component.t()}}, Server.t()}
  def render_dom(dom, env, server_struct)

  # Also refused inside the traversal, which is where a template-nested dynamic tag lands. This
  # boundary clause exists because a raise-only traversal clause contributes nothing to the
  # function's inferred input domain, so without it the type checker refuses callers handing in
  # the very values the raise is for.
  def render_dom({:dynamic_tag, {value}, _attrs_dom, _children_dom}, _env, _server_struct)
      when not is_atom(value) and not is_binary(value) do
    raise ArgumentError, message: invalid_dynamic_tag_value_message(value)
  end

  def render_dom(dom, env, server_struct) do
    {tree, component_registry, mutated_server_struct} = render_tree(dom, env, server_struct)

    {print_node(tree, env.tag_name), component_registry, mutated_server_struct}
  end

  # TODO: Refactor once there is something akin to {...@vars} syntax
  # (it would be possible to pass page state as layout props this way).
  @doc """
  Renders the given page as its two projections: the HTML a document load is served, and the
  evaluated tree the same render is described by as data.

  Only the HTML has the mount data interpolated into it, since a cold document has no channel for
  that state but the markup it is sent. The tree keeps the placeholders verbatim and the mount
  data is returned beside it, for a caller that carries the two as separate fields. Both
  projections leave the Realtime placeholders for the caller to substitute.

  ## Examples

      iex> render_page(MyPage, %{param: "value"}, %Server{}, initial_page?: true)
      %{
        component_registry: %{"page" => %{module: MyPage, struct: %Component{state: %{a: 1, b: 2}}}},
        mount_data: %{
          actor_user_id: "123",
          asset_manifest: "{...}",
          component_registry: "Type.map([...])",
          page_module: "Type.atom(...)",
          page_params: "Type.map([...])",
          sync_counts: "{...}",
          sync_rows: "{...}"
        },
        server_struct: %Server{session: %{user_id: 123}},
        tree: [{:element, "div", [{"$key", [text: "k2xq91:0"]}], [{:text, "full page content including layout"}]}]
      }
  """
  @spec render_page(module, %{atom => any}, Server.t(), T.opts()) :: %{
          component_registry: %{String.t() => %{module: module, struct: Component.t()}},
          mount_data: %{
            actor_user_id: String.t(),
            asset_manifest: String.t(),
            component_registry: String.t(),
            page_module: String.t(),
            page_params: String.t(),
            sync_counts: String.t(),
            sync_rows: String.t()
          },
          server_struct: Server.t(),
          tree: tree
        }
  def render_page(page_module, params, server_struct, opts) do
    Context.with_actor(server_struct.user_id, fn ->
      render_page_as_actor(page_module, params, server_struct, opts)
    end)
  end

  # Queries evaluated during the render are filtered by the session user's policies, and the
  # actor reaches them through the process context: prop queries run deep inside the render,
  # with no server struct in their signatures.
  defp render_page_as_actor(page_module, params, server_struct, opts) do
    initial_page? = opts[:initial_page?] || false

    Carry.start()

    {page_component_struct, page_server_struct} =
      init_component(page_module, params, server_struct)

    page_digest = PageDigestRegistry.lookup(page_module)

    page_component_struct_with_emitted_context_before_rendering =
      page_component_struct
      |> put_initial_page_flag_context(initial_page?)
      |> put_page_digest_context(page_digest)
      |> put_page_mounted_flag_context(false)
      |> maybe_put_csrf_token_context(opts, initial_page?)
      |> maybe_put_instance_id_context(opts, initial_page?)
      |> put_user_context()

    {initial_tree, initial_component_registry, final_server_struct} =
      render_page_inside_layout(
        page_module,
        params,
        page_component_struct_with_emitted_context_before_rendering,
        page_server_struct
      )

    page_component_struct_with_emitted_context_after_rendering =
      page_component_struct_with_emitted_context_before_rendering
      |> put_initial_page_flag_context(false)
      |> put_page_mounted_flag_context(true)

    component_registry_with_page_struct =
      Map.put(
        initial_component_registry,
        "page",
        %{module: page_module, struct: page_component_struct_with_emitted_context_after_rendering}
      )

    # `$SELF_ECHOES_JS_PLACEHOLDER` is intentionally left unsubstituted, along with the two
    # sub-receipt tokens. Their values depend on the post-render `server.broadcasts`, which is a
    # `Hologram.Realtime` concern - keeping the renderer Realtime-agnostic means the controller
    # substitutes them, into the tree it prints and into the navigation payload as fields.

    # The rows this render read, and who read them - both spelled as JSON rather than as the
    # boxed terms the rest of the mount data carries, because both are read by the data layer
    # rather than by transpiled code: the rows go through the same ingest a frame does, and the
    # acting user is what binds the actor predicates of the queries the client re-runs.
    # Gathered first, because it answers what the render ASKED rather than what it read: a
    # permission check reads no rows, so the rows behind its answer are looked up once the
    # questions are all in - and they join what the page carries like any other rows.
    Carry.take_grant_scopes()
    |> Auth.carried_grants()
    |> Carry.collect()

    # The values a mount reads, grouped because they travel together. The HTML projection inlines
    # all seven, since a loaded document has no other channel for them. A navigation carries six
    # of them as payload fields instead - not the asset manifest, which is a global the initial
    # document sets once and a navigation therefore already has.
    #
    # Encoded through the CLIENT encoder, which strips server-only attribute values: the same page
    # served either way must not say more one way than the other.
    #
    # The rows and counts are escaped for the SCRIPT ELEMENT they are printed into, not only for
    # JSON: a row holds whatever was written to the database, and a `</script>` in a string ends
    # the element around it whatever the JavaScript is doing - the HTML parser reads the tag before
    # the JavaScript engine reads anything at all. `:html_safe` spells the `<` as an escape, which
    # is the same string to a JSON reader and nothing to an HTML one.
    mount_data_js = %{
      actor_user_id: Jason.encode!(server_struct.user_id, escape: :html_safe),
      asset_manifest: AssetManifestCache.get_manifest_js(),
      component_registry: Encoder.encode_client_term!(component_registry_with_page_struct),
      page_module: Encoder.encode_client_term!(page_module),
      page_params: Encoder.encode_client_term!(params),
      sync_counts: Jason.encode!(Carry.take_counts(), escape: :html_safe),
      sync_rows: Jason.encode!(Carry.take(), escape: :html_safe)
    }

    # The tree keeps its placeholders. A navigation carries the mount data beside the tree rather
    # than inside it, so nothing on that path ever substitutes them - and folding the state into a
    # script element's text would only mean escaping encoder output into the tree's encoding and
    # unescaping it again on arrival. The document path substitutes them into the tree it prints,
    # which is the caller's to do, since only the caller holds the Realtime values that go in the
    # same pass.
    %{
      component_registry: component_registry_with_page_struct,
      mount_data: mount_data_js,
      server_struct: final_server_struct,
      tree: initial_tree
    }
  end

  @doc """
  Renders the given DOM into an evaluated tree: expressions evaluated, components flattened into
  the nodes their templates render, slots expanded, attribute values collapsed to single strings.
  Text and attribute values are held unescaped - escaping is a projection concern, and belongs to
  whatever prints the tree.

  WARNING: the evaluated tree is shipped to the client on navigation and converted to vnodes by
  the client renderer, which then must produce exactly what the client's own render of the same
  page produces - otherwise hydration rebuilds nodes instead of adopting them. Every
  normalization step here must therefore match the client renderer (renderer.mjs), clause by
  clause.

  ## Examples

      iex> dom = {:element, "div", [{"class", [text: "big"]}], [{:text, "Hologram"}]}
      iex> render_tree(dom, %Env{}, %Server{})
      {{:element, "div", [{"class", [text: "big"]}], [{:text, "Hologram"}]}, %{}, %Server{}}
  """
  @spec render_tree(DOM.t(), Env.t(), Server.t()) ::
          {tree, %{String.t() => %{module: module, struct: Component.t()}}, Server.t()}
  def render_tree(dom, env, server_struct)

  def render_tree({:component, module, props_dom, children_dom}, env, server_struct) do
    expanded_children_dom = expand_slots(children_dom, env.slots)

    props =
      props_dom
      |> cast_props(module)
      |> inject_props_from_context(module, env.context)
      |> inject_default_prop_values(module)
      |> inject_props_from_query(module)
      |> validate_props(module, env.parent_module)

    if has_cid_prop?(props) do
      render_stateful_component(
        module,
        props,
        expanded_children_dom,
        env.context,
        server_struct,
        env.parent_module
      )
    else
      render_template(
        module,
        props,
        expanded_children_dom,
        env.context,
        server_struct,
        env.parent_module
      )
    end
  end

  # A dynamic tag decides between the element and the component branch at render time, then behaves
  # exactly like the equivalent static tag would. That includes its spelling: a name that only
  # exists once the page renders is out of the compiler's reach, so it is spelled the way the
  # parser would spell it here instead.
  def render_tree({:dynamic_tag, {tag_name}, attrs_dom, children_dom}, env, server_struct)
      when is_binary(tag_name) do
    render_tree(
      {:element, Helpers.normalize_tag_name(tag_name), attrs_dom, children_dom},
      env,
      server_struct
    )
  end

  def render_tree({:dynamic_tag, {module}, props_dom, children_dom}, env, server_struct)
      when is_atom(module) do
    if Reflection.component?(module) do
      render_tree({:component, module, props_dom, children_dom}, env, server_struct)
    else
      raise ArgumentError,
        message: invalid_dynamic_tag_value_message(module) <> ", which is not a component module"
    end
  end

  def render_tree({:dynamic_tag, {value}, _attrs_dom, _children_dom}, _env, _server_struct) do
    raise ArgumentError, message: invalid_dynamic_tag_value_message(value)
  end

  # Kept in the tree for the HTML projection. The client renderer renders a doctype to nothing,
  # since the document it patches already has one.
  def render_tree({:doctype, content}, _env, server_struct) do
    {{:doctype, content}, %{}, server_struct}
  end

  def render_tree({:element, "slot", _attrs_dom, []}, %Env{} = env, server_struct) do
    # Slot content was written in the template that supplied it, not in the one holding the <slot />,
    # so a component in it belongs to the supplier. Without this a page's whole template would be
    # attributed to its layout, since a page's DOM is the layout's slot content.
    render_tree(
      env.slots[:default],
      %Env{env | slots: [], parent_module: env.slots_parent_module},
      server_struct
    )
  end

  # The <window> and <document> tags bind events to the window or document on the client. They have
  # no server rendering - they produce no markup and no hydration node.
  def render_tree({:element, tag_name, _attrs_dom, []}, _env, server_struct)
      when tag_name in ["window", "document"] do
    {nil, %{}, server_struct}
  end

  # Children of a void element are rendered even though no projection shows them, so that whatever
  # side effects the render has (component inits, server struct mutations) do not depend on the
  # tag they happen to sit in.
  def render_tree({:element, tag_name, attrs_dom, children_dom}, %Env{} = env, server_struct) do
    attributes = render_tree_attributes(attrs_dom)

    children_env = %Env{env | node_type: :element, tag_name: tag_name}

    {children, component_registry, mutated_server_struct} =
      render_tree(children_dom, children_env, server_struct)

    {{:element, tag_name, attributes, children}, component_registry, mutated_server_struct}
  end

  # An expression evaluated inside a script element is escaped at evaluation, unlike every other
  # text in the tree, which is held unescaped and escaped by whatever prints it. This is
  # deliberate: in the tree the value merges with the script's literal code, which is the last
  # moment the two are distinguishable, so the escaping that keeps a value from ending the script
  # element, and from ending the string literal the template wrote it into, has to happen here.
  #
  # WARNING: must match the client renderer's expression case (renderer.mjs), which escapes the
  # same characters the same way - see @script_text_escapes.
  def render_tree({:expression, {value}}, %Env{tag_name: "script"}, server_struct) do
    {{:text, stringify_for_script_interpolation(value)}, %{}, server_struct}
  end

  def render_tree({:expression, {value}}, _env, server_struct) do
    {{:text, to_string(value)}, %{}, server_struct}
  end

  def render_tree({:public_comment, children_dom}, %Env{} = env, server_struct) do
    children_env = %Env{env | node_type: :public_comment}

    {children, component_registry, mutated_server_struct} =
      render_tree(children_dom, children_env, server_struct)

    {{:public_comment, children}, component_registry, mutated_server_struct}
  end

  def render_tree({:text, text}, _env, server_struct) do
    {{:text, text}, %{}, server_struct}
  end

  # WARNING: must match the client renderer's #renderNodes step for step: filter out nil input
  # nodes, render each node, splice one level of node lists (a component renders to a list), then
  # merge adjacent text nodes. List.wrap/1 also drops nil render results (<window>, <document>),
  # which the client's merge step does.
  def render_tree(nodes, env, server_struct) when is_list(nodes) do
    # There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if}
    {rendered_nodes, component_registry, mutated_server_struct} =
      nodes
      |> Enum.filter(& &1)
      |> Enum.reduce({[], %{}, server_struct}, fn node,
                                                  {acc_nodes, acc_component_registry,
                                                   acc_server_struct} ->
        {tree, component_registry, mutated_server_struct} =
          render_tree(node, env, acc_server_struct)

        {acc_nodes ++ List.wrap(tree), Map.merge(acc_component_registry, component_registry),
         mutated_server_struct}
      end)

    {merge_neighbouring_text_nodes(rendered_nodes), component_registry, mutated_server_struct}
  end

  @doc """
  Converts a value to the text it contributes to a script element: its string form, escaped as
  the text of a JavaScript string literal.

  Every character that could end the literal, end the script element or be altered by the HTML
  parser on the way in is written as an escape sequence that reads back as that character, and
  every other character travels as itself. The value therefore reaches the script unchanged when
  the template writes it between quotes of any kind, and it can never end the script it is part
  of.

  ## Examples

      iex> stringify_for_script_interpolation("hello")
      "hello"

      iex> stringify_for_script_interpolation(~s(say "hi"))
      ~S(say \\"hi\\")

      iex> stringify_for_script_interpolation("</script>")
      ~S(\\u{3C}/script>)
  """
  @spec stringify_for_script_interpolation(any) :: String.t()
  def stringify_for_script_interpolation(value) do
    value
    |> to_string()
    |> String.replace(@script_text_escapable_chars, &Map.fetch!(@script_text_escapes, &1))
  end

  defp build_layout_props_dom(page_module, page_state) do
    page_module.__layout_props__()
    |> Enum.into(%{cid: "layout"})
    |> Map.merge(page_state)
    |> Enum.map(fn {name, value} -> {to_string(name), [expression: {value}]} end)
  end

  defp cast_props(props_dom, module) do
    props_dom
    |> expand_prop_spreads()
    |> filter_allowed_props(module)
    |> Stream.map(&evaluate_prop_value/1)
    |> Stream.map(&normalize_prop_name/1)
    |> Enum.into(%{})
  end

  # HTML attribute names are dash-separated, while Elixir identifiers can't contain dashes, so each
  # name segment converts to the convention of the namespace it lands in. Nesting composes the
  # segments with hyphens, e.g. %{data: %{user_id: 1}} becomes "data-user-id".
  # A flat run of alternating names and values rather than a pair per attribute: the run allocates
  # one array where pairs allocate one per attribute, and it is the cheapest source for the
  # attribute object the client builds out of it.
  defp encode_attributes(attributes) do
    Enum.flat_map(attributes, fn
      {name, [text: value]} -> [name, value]
      {name, []} -> [name, nil]
    end)
  end

  defp encode_node({:doctype, content}), do: ["d", content]

  defp encode_node({:element, tag_name, attributes, children}) do
    [tag_name, encode_attributes(attributes), Enum.map(children, &encode_node/1)]
  end

  defp encode_node({:public_comment, children}) do
    ["c", Enum.map(children, &encode_node/1)]
  end

  defp encode_node({:text, text}), do: text

  defp compose_attribute_name(key, name_prefix) do
    segment =
      key
      |> to_string()
      |> validate_spread_key()
      |> String.replace("_", "-")

    if name_prefix, do: name_prefix <> "-" <> segment, else: segment
  end

  # Event attributes are exempt from deduplication, because a tag may carry multiple bindings which
  # share a base name once their modifiers are decomposed at compile time, e.g. both
  # $key_down.enter and $key_down.esc are named "$key_down".
  defp dedupe_attributes(attrs_dom) do
    attrs_dom
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.uniq_by(fn {attr_dom, index} ->
      name = elem(attr_dom, 0)
      if String.starts_with?(name, "$"), do: {name, index}, else: name
    end)
    |> Enum.reverse()
    |> Enum.map(fn {attr_dom, _index} -> attr_dom end)
  end

  # WARNING: must match the client renderer's #valueDomToText: parts evaluate raw and concatenate,
  # with no escaping - the value lands in the DOM through setAttribute on the client, and the HTML
  # projection escapes at print time.
  defp evaluate_attribute_value(value_dom) do
    Enum.map_join(value_dom, fn
      {:text, text} -> text
      {:expression, {value}} -> to_string(value)
    end)
  end

  defp evaluate_prop_value({name, [expression: {value}]}) do
    {name, value}
  end

  defp evaluate_prop_value({name, [expression: value]}) do
    {name, value}
  end

  defp evaluate_prop_value({name, value_dom}) do
    {value_str, %{}, _server_struct} =
      render_dom(value_dom, %Env{node_type: :property}, %Server{})

    {name, value_str}
  end

  defp expand_attribute(attr_dom)

  # A spread's own entries are sorted by name, so that rendering is reproducible: map key order is
  # undefined in Erlang, and a keyword list's order decides only which duplicate key wins, never how
  # the surviving entries are laid out. The sort is stable, which is what keeps that later-wins rule
  # intact. Only the block a single spread expands to is sorted, so attributes written literally in
  # the markup keep their authored position.
  defp expand_attribute({:spread, {value}}) do
    value
    |> expand_spread_attributes(nil)
    |> Enum.sort_by(fn {name, _value_dom} -> name end)
  end

  defp expand_attribute(attr_dom), do: [attr_dom]

  # Spread entries are splatted into synthetic named attributes at the spread's position, so that
  # everything downstream (event attribute filtering, boolean attribute rules, value rendering) is
  # reached through the same path as attributes written literally in the markup. Names then resolve
  # positionally, last one wins.
  defp expand_attribute_spreads(attrs_dom) do
    if Enum.any?(attrs_dom, &match?({:spread, _value}, &1)) do
      attrs_dom
      |> Enum.flat_map(&expand_attribute/1)
      |> dedupe_attributes()
    else
      attrs_dom
    end
  end

  defp expand_prop(prop_dom)

  defp expand_prop({:spread, {value}}), do: expand_spread_props(value)

  defp expand_prop(prop_dom), do: [prop_dom]

  # Spread entries are splatted into synthetic named props at the spread's position, so that
  # everything downstream (filtering to declared props, name normalization, context injection,
  # defaults, cid detection) is reached through the same path as props written literally in the
  # markup. Names then resolve positionally, last one wins, which the final collapse into a map
  # already does - no deduplication step is needed here.
  defp expand_prop_spreads(props_dom) do
    if Enum.any?(props_dom, &match?({:spread, _value}, &1)) do
      Enum.flat_map(props_dom, &expand_prop/1)
    else
      props_dom
    end
  end

  defp expand_slots(dom, slots)

  defp expand_slots(nodes, slots) when is_list(nodes) do
    nodes
    |> Enum.map(&expand_slots(&1, slots))
    |> List.flatten()
  end

  defp expand_slots({:component, module, props_dom, children_dom}, slots) do
    {:component, module, props_dom, expand_slots(children_dom, slots)}
  end

  defp expand_slots({:dynamic_tag, {value}, attrs_dom, children_dom}, slots) do
    {:dynamic_tag, {value}, attrs_dom, expand_slots(children_dom, slots)}
  end

  defp expand_slots({:element, "slot", _attrs_dom, []}, slots) do
    slots[:default]
  end

  defp expand_slots({:element, tag_name, attrs_dom, children_dom}, slots) do
    {:element, tag_name, attrs_dom, expand_slots(children_dom, slots)}
  end

  defp expand_slots(node, _slots), do: node

  defp expand_spread_attribute({key, value}, name_prefix) do
    name = compose_attribute_name(key, name_prefix)

    if nested_spread_value?(value) do
      expand_spread_attributes(value, name)
    else
      [{name, [expression: {value}]}]
    end
  end

  defp expand_spread_attributes(value, name_prefix) do
    value
    |> spread_entries()
    |> Enum.flat_map(&expand_spread_attribute(&1, name_prefix))
  end

  # Props live in the Elixir namespace, so unlike attribute names they are verbatim and flat - a map
  # or keyword list entry value is simply a raw prop value, and doesn't compose a nested name.
  defp expand_spread_props(value) do
    value
    |> spread_entries()
    |> Enum.map(fn {key, entry_value} ->
      name =
        key
        |> to_string()
        |> validate_spread_key()

      {name, [expression: {entry_value}]}
    end)
  end

  defp filter_allowed_props(props_dom, module) do
    registered_prop_names =
      module.__props__()
      |> Enum.reject(fn {_name, _type, opts} -> opts[:from_context] || opts[:from_query] end)
      |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)

    allowed_prop_names = ["cid" | registered_prop_names]

    Enum.filter(props_dom, fn {name, _value_dom} -> name in allowed_prop_names end)
  end

  defp from_query_arg!(module, prop_name, nil, _props) do
    raise ArgumentError,
      message:
        "from_query capture for prop #{inspect(prop_name)} in #{inspect(module)} has an argument position no clause names - it cannot bind a prop"
  end

  defp from_query_arg!(module, prop_name, param_name, props) do
    case Map.fetch(props, param_name) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
          message:
            "from_query for prop #{inspect(prop_name)} in #{inspect(module)} binds argument #{inspect(param_name)} - no like-named prop is set"
    end
  end

  defp from_query_args!(_module, _prop_name, capture, _props) when is_function(capture, 0) do
    []
  end

  defp from_query_args!(module, prop_name, _capture, props) do
    param_names = QueryCache.prop_params(module, prop_name)

    if param_names == nil do
      raise ArgumentError,
        message:
          "no registered params for from_query prop #{inspect(prop_name)} in #{inspect(module)} - the query cache holds no entry for it"
    end

    Enum.map(param_names, &from_query_arg!(module, prop_name, &1, props))
  end

  defp has_cid_prop?(props) do
    Enum.any?(props, fn {name, _value} -> name == :cid end)
  end

  defp init_component(module, props, server_struct) do
    init_result =
      if Reflection.has_function?(module, :init, 3) do
        module.init(props, %Component{}, server_struct)
      else
        {%Component{}, server_struct}
      end

    {component_struct, returned_server_struct} =
      case init_result do
        {component_struct, mutaded_server_struct} ->
          {component_struct, mutaded_server_struct}

        %Component{} = component_struct ->
          {component_struct, server_struct}

        %Server{} = mutated_server_struct ->
          {%Component{}, mutated_server_struct}
      end

    {component_struct, %{returned_server_struct | cid: nil}}
  end

  defp inject_default_prop_values(props, module) do
    Enum.reduce(module.__props__(), props, fn {name, _type, opts}, acc ->
      if !Map.has_key?(acc, name) && Keyword.has_key?(opts, :default) do
        Map.put(acc, name, Keyword.get(opts, :default))
      else
        acc
      end
    end)
  end

  defp inject_props_from_context(props, module, context) do
    props_from_context =
      module.__props__()
      |> Enum.filter(fn {_name, _type, opts} ->
        opts[:from_context] && Map.has_key?(context, opts[:from_context])
      end)
      |> Enum.map(fn {name, _type, opts} -> {name, context[opts[:from_context]]} end)
      |> Enum.into(%{})

    Map.merge(props, props_from_context)
  end

  # Runs after the other prop sources - a parameterized query capture binds
  # like-named props, which template values, context, and defaults supply.
  # Every query reads its arguments from the props the component was GIVEN, never from the
  # accumulator - so what one query answers can never reach another's arguments, and the order
  # these run in cannot change what any of them returns. The build refuses such a binding
  # outright; this is the same rule holding by construction rather than by check.
  defp inject_props_from_query(props, module) do
    module.__props__()
    |> Enum.filter(fn {_name, _type, opts} -> opts[:from_query] end)
    |> Enum.reduce(props, fn {name, _type, opts}, acc ->
      Map.put(acc, name, run_prop_query!(module, name, opts[:from_query], props))
    end)
  end

  # A `$` inside an inserted value cannot begin a token once it is spelled as an escape, and the
  # string it sits in says the same thing either way: `\u0024` is `$` to a JSON reader and to a
  # JavaScript one alike. Only the `$` moves - the rest of the token is ordinary text.
  defp neutralize_js_placeholders(js) do
    Regex.replace(@js_placeholder_pattern, js, fn <<?$, rest::binary>> ->
      "\\u0024" <> rest
    end)
  end

  defp invalid_dynamic_tag_value_message(value) do
    "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: #{inspect(value)}"
  end

  defp maybe_put_csrf_token_context(page_component_struct, opts, true) do
    csrf_token =
      opts[:csrf_token] || raise ArgumentError, "CSRF token is required for initial page requests"

    Component.put_context(
      page_component_struct,
      {Hologram, :csrf_token},
      csrf_token
    )
  end

  defp maybe_put_csrf_token_context(page_component_struct, _opts, false) do
    page_component_struct
  end

  defp maybe_put_instance_id_context(page_component_struct, opts, true) do
    instance_id =
      opts[:instance_id] ||
        raise ArgumentError, "instance_id is required for initial page requests"

    Component.put_context(
      page_component_struct,
      {Hologram, :instance_id},
      instance_id
    )
  end

  defp maybe_put_instance_id_context(page_component_struct, _opts, false) do
    page_component_struct
  end

  # WARNING: must match the client renderer's #mergeNeighbouringTextNodes: adjacent text nodes
  # join into one, other nodes pass through. Merged text is also what an HTML parser produces, so
  # the tree stays in the one form the live DOM can hold.
  defp merge_neighbouring_text_nodes(nodes) do
    nodes
    |> Enum.reduce([], fn
      {:text, text}, [{:text, preceding_text} | rest] ->
        [{:text, preceding_text <> text} | rest]

      node, acc ->
        [node | acc]
    end)
    |> Enum.reverse()
  end

  # Maps and keyword lists compose nested attribute names, everything else is a leaf value. Structs
  # are excluded, since they are ordinary values which stringify through String.Chars, e.g. Date.
  defp nested_spread_value?(value) do
    (is_map(value) and not is_struct(value)) or (is_list(value) and Keyword.keyword?(value))
  end

  defp normalize_prop_name({name, value}) do
    {String.to_existing_atom(name), value}
  end

  defp print_attribute({name, []}), do: name

  defp print_attribute({name, [text: ""]}), do: name

  defp print_attribute({name, [text: value]}) do
    ~s(#{name}="#{HtmlEntities.encode(value)}")
  end

  defp print_attributes(attributes) do
    attributes
    |> Enum.reject(fn {name, _value} -> String.starts_with?(name, "$") end)
    |> Enum.map_join(" ", &print_attribute/1)
    |> StringUtils.prepend_if_not_empty(" ")
  end

  # The tag the printed node sits in travels down, since it decides whether text is markup or
  # code. A comment passes it along rather than clearing it: "<!--" inside a script opens no
  # comment, so escaping the text it wraps would corrupt the code it belongs to.
  defp print_node(nodes, parent_tag_name) when is_list(nodes) do
    Enum.map_join(nodes, &print_node(&1, parent_tag_name))
  end

  # A <window> or <document> tag renders to no node at all.
  defp print_node(nil, _parent_tag_name), do: ""

  defp print_node({:doctype, content}, _parent_tag_name), do: "<!DOCTYPE #{content}>"

  defp print_node({:element, tag_name, attributes, children}, _parent_tag_name) do
    attributes_html = print_attributes(attributes)

    if tag_name in @void_elems do
      "<#{tag_name}#{attributes_html} />"
    else
      children_html = print_node(children, tag_name)

      "<#{tag_name}#{attributes_html}>#{children_html}</#{tag_name}>"
    end
  end

  defp print_node({:public_comment, children}, parent_tag_name) do
    "<!--#{print_node(children, parent_tag_name)}-->"
  end

  defp print_node({:text, text}, "script"), do: text

  defp print_node({:text, text}, _parent_tag_name), do: HtmlEntities.encode(text)

  defp put_initial_page_flag_context(page_component_struct, initial_page?) do
    Component.put_context(
      page_component_struct,
      {Hologram, :initial_page?},
      initial_page?
    )
  end

  defp put_page_digest_context(page_component_struct, page_digest) do
    Component.put_context(
      page_component_struct,
      {Hologram, :page_digest},
      page_digest
    )
  end

  defp put_page_mounted_flag_context(page_component_struct, page_mounted?) do
    Component.put_context(
      page_component_struct,
      {Hologram, :page_mounted?},
      page_mounted?
    )
  end

  # The row is handed over already carrying the sentinel, so the server-rendered HTML and the
  # client re-render agree on framework-delivered rows.
  defp put_user_context(page_component_struct) do
    user =
      RoleGrant.user_entity()
      |> read_session_user(Auth.user_id())
      |> Entity.strip_server_only_deep()

    Component.put_context(page_component_struct, {Hologram, :user}, user)
  end

  defp raise_invalid_spread_value(value) do
    raise ArgumentError,
      message: "spread value must be a map or a keyword list, got: #{inspect(value)}"
  end

  # The session user's row, read through the policied path - the framework grants itself
  # no bypass, so the value is the row AS VISIBLE to that user: nil when the user entity's
  # read rules deny it (or none matches the own row), nil when anonymous, nil when no user
  # entity is designated. A session user id that is not a canonical entity id also yields
  # nil - the session's user_id keeps its wider latitude for apps not using the data layer.
  defp read_session_user(nil, _user_id), do: nil

  defp read_session_user(user_entity, user_id) do
    if Validator.attribute_value_valid?(user_id, :uuid) do
      term =
        user_entity
        |> Query.filter(id: user_id)
        |> Query.one()
        |> Query.normalize()

      QueryRunner.run_policied(term, DB.mapping(), user_id)
    end
  end

  # Naming the template the component was rendered from is what turns the error into something
  # actionable - a component used in thirty places says nothing on its own. A top-level render has
  # no parent, and then the message simply ends after the prop.
  defp rendered_from(nil), do: ""

  defp rendered_from(module), do: ~s/, rendered from "#{Reflection.module_name(module)}"/

  defp render_page_inside_layout(
         page_module,
         params,
         %{
           emitted_context: page_emitted_context,
           state: page_state
         },
         server_struct
       ) do
    vars = Map.merge(params, page_state)
    page_dom = page_module.template().(vars)

    layout_module = page_module.__layout_module__()
    layout_props_dom = build_layout_props_dom(page_module, page_state)
    layout_node = {:component, layout_module, layout_props_dom, page_dom}

    render_tree(
      layout_node,
      %Env{context: page_emitted_context, parent_module: page_module},
      server_struct
    )
  end

  defp render_stateful_component(
         module,
         props,
         children_dom,
         context,
         server_struct,
         parent_module
       ) do
    server_struct = %{server_struct | cid: props.cid}
    {component_struct, mutated_server_struct} = init_component(module, props, server_struct)

    vars = Map.merge(props, component_struct.state)
    merged_context = Map.merge(context, component_struct.emitted_context)

    {tree, children_component_registry, final_server_struct} =
      render_template(
        module,
        vars,
        children_dom,
        merged_context,
        mutated_server_struct,
        parent_module
      )

    component_registry =
      Map.put(children_component_registry, vars.cid, %{module: module, struct: component_struct})

    {tree, component_registry, final_server_struct}
  end

  # parent_module is the module whose template holds this usage - it owns the slot content passed in,
  # while the template about to be rendered owns everything written inside it.
  defp render_template(module, vars, children_dom, context, server_struct, parent_module) do
    env = %Env{
      context: context,
      parent_module: module,
      slots: [default: children_dom],
      slots_parent_module: parent_module
    }

    vars
    |> module.template().()
    |> render_tree(env, server_struct)
  end

  # WARNING: must match the client renderer's #renderAttribute normalization: an empty value list
  # is a boolean attribute, a nil or false expression value removes the attribute, and everything
  # else collapses to one unescaped string.
  defp render_tree_attribute(attr_dom)

  defp render_tree_attribute({name, []}), do: {name, []}

  defp render_tree_attribute({_name, [expression: {nil}]}), do: nil

  defp render_tree_attribute({_name, [expression: {false}]}), do: nil

  defp render_tree_attribute({name, value_dom}) do
    {name, [text: evaluate_attribute_value(value_dom)]}
  end

  # Event bindings stay behind: they are built from compile-time listener information the tree
  # cannot carry, and the interim page a navigation patches in is display-only until hydration
  # attaches real listeners. The `$key` attribute travels, since it is what carries element
  # identity into the client's diff.
  defp render_tree_attributes(attrs_dom)

  defp render_tree_attributes([]), do: []

  defp render_tree_attributes(attrs_dom) do
    attrs_dom
    |> expand_attribute_spreads()
    |> Enum.reject(fn attr_dom ->
      name = elem(attr_dom, 0)
      String.starts_with?(name, "$") and name != "$key"
    end)
    |> Enum.map(&render_tree_attribute/1)
    |> Enum.reject(&is_nil/1)
  end

  defp run_prop_query!(module, prop_name, capture, props) do
    args = from_query_args!(module, prop_name, capture, props)

    term =
      capture
      |> apply(args)
      |> Query.normalize()

    result =
      term
      |> QueryRunner.run_policied(DB.mapping(), Auth.user_id())
      |> Entity.strip_server_only_deep()

    # Gathered as the prop resolves, so the client is handed the rows this render read - which is
    # what lets its own first render answer the same query from its own database rather than from
    # a value passed down beside it.
    Carry.collect(result)

    # A count has no rows behind it, so carried rows cannot re-derive one - the number itself is
    # handed over, and the client holds it until its own database is complete enough to count.
    if is_integer(result) do
      Carry.collect_count(module, prop_name, args, result)
    end

    result
  end

  defp spread_entries(value)

  # Structs are maps, but their __struct__ key is not a name.
  defp spread_entries(%_struct{} = value), do: raise_invalid_spread_value(value)

  defp spread_entries(value) when is_map(value), do: Enum.to_list(value)

  defp spread_entries(value) when is_list(value) do
    if Keyword.keyword?(value), do: value, else: raise_invalid_spread_value(value)
  end

  defp spread_entries(value), do: raise_invalid_spread_value(value)

  # Runs last in the props pipeline, so the map it sees is exactly what the component's template
  # will see - defaults filled and context injected. The compiler already rejects a required prop
  # missing from a usage it can decide; what reaches here is what it can't: spreads, dynamic tags
  # and props sourced from context. Mirrored by #validateProps in renderer.mjs.
  defp validate_props(props, module, parent_module) do
    Enum.each(module.__props__(), fn {name, _type, opts} ->
      validate_prop(props, name, opts, module, parent_module)
    end)

    props
  end

  # The compiler judges a value written in a template and a default written in a declaration, so what
  # is left here is what only exists once the page runs: a value from context, or one arriving
  # through a spread.
  defp validate_prop(props, name, opts, module, parent_module) do
    cond do
      opts[:required] && !Map.has_key?(props, name) ->
        raise Hologram.PropError,
          message:
            ~s/component "#{Reflection.module_name(module)}" is missing required prop "#{name}"/ <>
              rendered_from(parent_module)

      opts[:values] && Map.has_key?(props, name) && props[name] not in opts[:values] ->
        raise Hologram.PropError,
          message:
            ~s/prop "#{name}" of component "#{Reflection.module_name(module)}" must be one of / <>
              "#{inspect(opts[:values])}, got: #{inspect(props[name])}" <>
              rendered_from(parent_module)

      true ->
        :ok
    end
  end

  # Event bindings require compile-time modifier parsing and listener collection, so they can be
  # written only as literal attributes. Silently not binding an intended event would be worse than
  # erroring here.
  defp validate_spread_key("$" <> _rest = key) do
    raise ArgumentError,
      message: "event bindings can't be set through a spread, got the #{inspect(key)} key"
  end

  defp validate_spread_key(key), do: key
end
