defmodule HologramFeatureTests.TemplateSyntax.PublicCommentPage do
  use Hologram.Page

  route "/template-syntax/public-comment"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <div>
      <span>abc<!-- my comment -->xyz</span>
    </div>
    """
  end
end
