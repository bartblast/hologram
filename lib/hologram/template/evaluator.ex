defprotocol Hologram.Template.Evaluator do
  @fallback_to_any true

  def evaluate(ir, state)
end
