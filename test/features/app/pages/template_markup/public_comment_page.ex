defmodule HologramFeatureTests.TemplateMarkup.PublicCommentPage do
  use Hologram.Page

  route "/template-markup/public-comment"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~H"""
    <div>
      <span>abc<!-- my comment -->xyz</span>
    </div>
    """
  end
end
