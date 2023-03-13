defprotocol Hologram.Template.Encoder do
  alias Hologram.Typespecs, as: T

  @doc """
  Given VDOM template, generates virtual DOM template JS representation,
  which can be used by the frontend runtime to re-render the VDOM.

  ## Examples
      iex> encode(%ElementNode{tag: "div", children: [%TextNode{content: "test}]})
      "{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'test' }] }"
  """
  @spec encode(T.vdom_node() | list(T.vdom_node())) :: String.t()

  def encode(vdom)
end
