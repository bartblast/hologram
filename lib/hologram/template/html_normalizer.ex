defmodule Hologram.Template.HTMLNormalizer do
  @moduledoc false

  # Where content sits, as the browser's parser sees it when it reads a start tag there:
  #
  #   :html           - HTML content, where <svg> and <math> open foreign content
  #   :svg            - SVG content
  #   :math           - MathML content
  #   :annotation_xml - MathML content of an annotation-xml element without an HTML encoding,
  #                     where <svg> opens SVG content
  #   :mathml_text    - content of a MathML text integration point (mi, mo, ...), read as HTML
  #                     except for <mglyph> and <malignmark>, which stay MathML
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#tree-construction-dispatcher
  @type context :: :annotation_xml | :html | :math | :mathml_text | :svg

  @type namespace :: :html | :math | :svg

  # The text of the comments a trusted HTML range is printed between. The client finds the range in
  # a server-rendered page by them, so content carrying a comment with the same text could end the
  # range early - such comments are dropped from the content.
  #
  # WARNING: must match TRUSTED_HTML_RANGE_START and TRUSTED_HTML_RANGE_END in the client (vdom.mjs).
  @range_start_marker "hologram-html"
  @range_end_marker "/hologram-html"

  # The parents whose content the browser's parser reads in an insertion mode of its own - a table
  # one, the column group one, or the template one - with the elements that put the parser in that
  # mode. Plain parsing reads in body mode, which drops <tr>, <td>, <col> and the like as misplaced.
  # Inside the real table structure the parser also adds the elements a table implies, as the
  # browser does - a <tbody> around rows put straight into a <table>, a <tr> around cells put
  # straight into a <tbody> - and the client's innerHTML adds the same ones.
  @mode_wrappers %{
    "colgroup" => ["table", "colgroup"],
    "table" => ["table"],
    "tbody" => ["table", "tbody"],
    "template" => ["template"],
    "tfoot" => ["table", "tfoot"],
    "thead" => ["table", "thead"],
    "tr" => ["table", "tbody", "tr"]
  }

  @mode_wrapped_parents Map.keys(@mode_wrappers)

  # The elements dropped from the content, wherever they are, because they would behave differently
  # on a first page than after a client update, which inserts content through innerHTML:
  #
  #   script    - runs when the browser parses the page, never through innerHTML
  #   plaintext - turns everything after it on the page into text
  #   noscript  - lexbor parses with scripting off, so its content is markup in the tree, while
  #               the browser reads it as raw text up to the first </noscript, so printed markup
  #               could end it early and let what follows out - a script included. It shows
  #               nothing to a browser running JavaScript anyway.
  #
  # WARNING: must match TRUSTED_HTML_DROPPED_ELEMENTS in the client (vdom.mjs), as must the
  # shadowroot* attributes removed in print_element/4, or a range the server printed wouldn't be the
  # range the client builds from the same HTML.
  @dropped_elements ~w(noscript plaintext script)

  # The HTML elements serialized without an end tag or content.
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#serializes-as-void
  @void_elements ~w(area base basefont bgsound br col embed frame hr img input keygen link meta param source track wbr)

  # The HTML elements whose text is serialized as it is, since the parser reads it without decoding
  # entities. plaintext is dropped before it gets here.
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#serialising-html-fragments
  @raw_text_elements ~w(iframe noembed noframes style xmp)

  # The HTML elements whose content loses a line feed right after the start tag when parsed.
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody
  @leading_line_feed_elements ~w(listing pre textarea)

  # The SVG elements whose content the parser reads as HTML.
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#html-integration-point
  @svg_html_integration_points ~w(desc foreignObject title)

  # See: https://html.spec.whatwg.org/multipage/parsing.html#mathml-text-integration-point
  @mathml_text_integration_points ~w(mi mn mo ms mtext)

  @doc """
  Returns the context the content of an element with the given tag name, attributes and namespace
  sits in (see `t:context/0`).

  ## Examples

      iex> children_context("foreignObject", [], :svg)
      :html

      iex> children_context("g", [], :svg)
      :svg
  """
  @spec children_context(String.t(), [{String.t(), String.t()}], namespace) :: context
  def children_context(tag_name, attrs, namespace)

  def children_context(_tag_name, _attrs, :html), do: :html

  def children_context(tag_name, _attrs, :svg) when tag_name in @svg_html_integration_points,
    do: :html

  def children_context(_tag_name, _attrs, :svg), do: :svg

  def children_context(tag_name, _attrs, :math) when tag_name in @mathml_text_integration_points,
    do: :mathml_text

  def children_context("annotation-xml", attrs, :math) do
    encoding =
      attrs
      |> Enum.find_value("", fn {name, value} -> name == "encoding" && value end)
      |> String.downcase()

    if encoding in ["text/html", "application/xhtml+xml"], do: :html, else: :annotation_xml
  end

  def children_context(_tag_name, _attrs, :math), do: :math

  @doc """
  Returns the namespace an element with the given tag name is in when it sits in the given context
  (see `t:context/0`).

  ## Examples

      iex> element_namespace("svg", :html)
      :svg

      iex> element_namespace("p", :svg)
      :svg
  """
  @spec element_namespace(String.t(), context) :: namespace
  def element_namespace(tag_name, context)

  def element_namespace("svg", context) when context in [:annotation_xml, :html, :mathml_text],
    do: :svg

  def element_namespace("math", context) when context in [:html, :mathml_text], do: :math

  def element_namespace(tag_name, :mathml_text) when tag_name in ["malignmark", "mglyph"],
    do: :math

  def element_namespace(_tag_name, context) when context in [:html, :mathml_text], do: :html

  def element_namespace(_tag_name, :svg), do: :svg

  def element_namespace(_tag_name, context) when context in [:annotation_xml, :math], do: :math

  @doc """
  Returns the given trusted HTML the way the browser's parser reads it when the client inserts it
  under a parent with the given tag name, in the given context (see `t:context/0`), so the markup
  around it on the page stays as the template wrote it: unclosed elements are closed and stray end
  tags dropped. Content that isn't valid where it's placed - a <div> inside a <p> - can still be
  moved by the browser when it parses the page, which the client reports at hydration.

  What would behave differently on a first page than after a client update is dropped or
  neutralized: script, plaintext and noscript elements (see `@dropped_elements`), and the
  shadowroot* attributes of template elements, which would attach a shadow root to the parent
  when the browser parses the page and are ignored by innerHTML. So are comments whose text is a
  range marker.

  ## Examples

      iex> normalize("<div><b>bold", "p", :html)
      "<div><b>bold</b></div>"

      iex> normalize("<tr><td>cell</td></tr>", "tbody", :html)
      "<tr><td>cell</td></tr>"

      iex> normalize("<tr><td>cell</td></tr>", "table", :html)
      "<tbody><tr><td>cell</td></tr></tbody>"

      iex> normalize("<p>text</p><script>alert(1)</script>", "div", :html)
      "<p>text</p>"
  """
  @spec normalize(String.t(), String.t() | nil, context) :: String.t()
  def normalize(html, parent_tag_name, context)

  def normalize(html, parent_tag_name, context)
      when context in [:html, :mathml_text] and parent_tag_name in @mode_wrapped_parents do
    wrappers = Enum.map(@mode_wrappers[parent_tag_name], &{&1, context})
    normalize_in_wrappers(html, wrappers)
  end

  def normalize(html, _parent_tag_name, context) when context in [:html, :mathml_text] do
    html
    |> parse()
    |> print_nodes(context, nil)
    |> IO.iodata_to_binary()
  end

  def normalize(html, _parent_tag_name, :svg) do
    normalize_in_wrappers(html, [{"svg", :svg}])
  end

  def normalize(html, _parent_tag_name, :math) do
    normalize_in_wrappers(html, [{"math", :math}])
  end

  def normalize(html, _parent_tag_name, :annotation_xml) do
    normalize_in_wrappers(html, [{"math", :math}, {"annotation-xml", :annotation_xml}])
  end

  @doc """
  Returns the text of the comment a trusted HTML range ends with.
  """
  @spec range_end_marker() :: String.t()
  def range_end_marker, do: @range_end_marker

  @doc """
  Returns the text of the comment a trusted HTML range starts with.
  """
  @spec range_start_marker() :: String.t()
  def range_start_marker, do: @range_start_marker

  # Whether a node is left out of the printed content: an element in @dropped_elements, or a comment
  # carrying a range marker.
  defp dropped_node?({:comment, text}), do: text in [@range_start_marker, @range_end_marker]

  defp dropped_node?({tag_name, _attrs, _children}), do: tag_name in @dropped_elements

  defp dropped_node?(_text), do: false

  defp escape_attribute_value(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace(" ", "&nbsp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace(" ", "&nbsp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # The parser drops a line feed right after a pre, a textarea or a listing start tag, so content
  # that starts with one is printed with another in front of it, which the browser drops instead.
  defp leading_line_feed(tag_name, :html, [<<"\n", _rest::binary>> | _nodes])
       when tag_name in @leading_line_feed_elements,
       do: "\n"

  defp leading_line_feed(_tag_name, _namespace, _children), do: ""

  # Content for a parent the browser reads in a mode of its own is parsed inside wrappers that put
  # the parser in that mode, each given with the context its content sits in. The parser can put
  # content outside a wrapper, and what it puts there is content too, printed in the context around
  # the wrapper: a stray end tag for a wrapper ends it early, so what follows becomes its siblings,
  # an HTML start tag such as <div> breaks out of an <svg> or a <math> wrapper the same way, and
  # what a table can't hold is moved before it.
  defp normalize_in_wrappers(html, wrappers) do
    {wrapper_tag_names, _contexts} = Enum.unzip(wrappers)

    opening = Enum.map(wrapper_tag_names, &"<#{&1}>")

    closing =
      wrapper_tag_names
      |> Enum.reverse()
      |> Enum.map(&"</#{&1}>")

    [opening, html, closing]
    |> IO.iodata_to_binary()
    |> parse()
    |> print_unwrapped(wrappers, :html)
    |> IO.iodata_to_binary()
  end

  # Parses the given HTML in the body of a document, as the browser parses a page. Lexbor's fragment
  # parsing doesn't break out of foreign content - an HTML start tag such as <p> stays inside an
  # <svg> - while browsers do, in fragments as well as documents. The body takes the content even
  # where a document's head would: a <title> or a <meta> starting the content stays in it.
  defp parse(html) do
    tree =
      ("<!DOCTYPE html><body>" <> html)
      |> LazyHTML.from_document()
      |> LazyHTML.to_tree()

    # A comment after a closing </html> in the content is put after the html element, outside the
    # body, so it's lost.
    {"html", _attrs, html_children} = Enum.find(tree, &match?({"html", _attrs, _children}, &1))
    {"body", _attrs, body_children} = List.keyfind(html_children, "body", 0)

    body_children
  end

  defp print_attributes(attrs) do
    Enum.map(attrs, fn {name, value} ->
      [" ", name, "=\"", escape_attribute_value(value), "\""]
    end)
  end

  defp print_element(tag_name, attrs, children, context) do
    namespace = element_namespace(tag_name, context)

    attrs =
      if tag_name == "template" and namespace == :html do
        Enum.reject(attrs, fn {name, _value} -> String.starts_with?(name, "shadowroot") end)
      else
        attrs
      end

    start_tag = ["<", tag_name, print_attributes(attrs), ">"]

    # Dropped before the leading line feed check, which a dropped node in front of the text would
    # otherwise hide.
    children = Enum.reject(children, &dropped_node?/1)

    if namespace == :html and tag_name in @void_elements do
      start_tag
    else
      raw_text_parent = if namespace == :html, do: tag_name
      children_context = children_context(tag_name, attrs, namespace)

      [
        start_tag,
        leading_line_feed(tag_name, namespace, children),
        print_nodes(children, children_context, raw_text_parent),
        "</",
        tag_name,
        ">"
      ]
    end
  end

  # Serializes the nodes of a tree LazyHTML.to_tree/1 returns, following the HTML fragment
  # serialization algorithm. LazyHTML.from_tree/1 can't be used to print them back: it knows no
  # MathML and doesn't switch back to HTML inside SVG's integration points, so it would print HTML
  # with foreign rules and the other way round - a <style> in SVG unescaped, a <br> in a
  # <foreignObject> with an end tag.
  #
  # See: https://html.spec.whatwg.org/multipage/parsing.html#serialising-html-fragments
  defp print_nodes(nodes, context, raw_text_parent) do
    nodes
    |> Enum.reject(&dropped_node?/1)
    |> Enum.map(fn
      {:comment, text} ->
        ["<!--", text, "-->"]

      {tag_name, attrs, children} ->
        print_element(tag_name, attrs, children, context)

      text when raw_text_parent in @raw_text_elements ->
        text

      text ->
        escape_text(text)
    end)
  end

  defp print_unwrapped(nodes, [], context), do: print_nodes(nodes, context, nil)

  # A wrapper is the first element with its tag name at its level: what the parser moves before a
  # table is never a table - a <table> the content opens in a table mode closes the open table
  # instead - and nothing is moved before any other wrapper.
  defp print_unwrapped(nodes, [{tag_name, inner_context} | inner_wrappers], context) do
    {preceding_nodes, [{^tag_name, _attrs, children} | following_nodes]} =
      Enum.split_while(nodes, &(not match?({^tag_name, _attrs, _children}, &1)))

    [
      print_nodes(preceding_nodes, context, nil),
      print_unwrapped(children, inner_wrappers, inner_context),
      print_nodes(following_nodes, context, nil)
    ]
  end
end
