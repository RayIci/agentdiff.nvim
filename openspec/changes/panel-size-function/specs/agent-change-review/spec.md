# Spec Delta

## MODIFIED Requirements

### Requirement: Panel window
The panel SHALL open at the side given by `panel.position` (`right` by default, or `left`, `top`, `bottom`) with the size given by `panel.size`: a fixed number of columns or rows, a share of the editor such as `"30%"` that follows the editor's size, or a function returning one of these, called again whenever the editor is resized. The panel window SHALL show only the panel buffer, and files opened from the panel or by navigation SHALL open in an editing window, never in the panel window.

#### Scenario: Position and size
- **WHEN** the host sets `panel = { position = "left", size = "25%" }` and the user opens the panel
- **THEN** it opens at the left edge, a quarter of the editor wide

#### Scenario: Files never open in the panel
- **WHEN** the panel is the current window and the user opens a file from it, runs a navigation action, or `:edit`s another file
- **THEN** the file opens in an editing window (a new split when there is none) and the panel window keeps showing the panel, or the `:edit` fails

#### Scenario: Size from a function
- **WHEN** the host sets `panel = { size = function(ctx) return math.max(45, math.floor(ctx.total * 0.3)) end }` and the editor is 100 columns wide, then resized to 200
- **THEN** the panel is 45 columns wide, then 60
