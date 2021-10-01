alias Hologram.Template.Document.TextNode
alias Hologram.Template.Evaluator

defimpl Evaluator, for: TextNode do
  def evaluate(%{content: content}, _) do
    content
  end
end
