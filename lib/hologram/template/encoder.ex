defprotocol Hologram.Template.Encoder do
  alias Hologram.Typespecs, as: T

  @doc """
  Given document tree template, generates virtual DOM template JS representation,
  which can be used by the frontend runtime to re-render the DOM.

  ## Examples
      iex> encode(%ElementNode{tag: "div", children: [%TextNode{content: "test}]})
      "{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'test' }] }"
  """
  @spec encode(T.document_node() | list(T.document_node())) :: String.t()

  def encode(document_tree)
end
