# Spec Delta

## ADDED Requirements

### Requirement: Optional integration modules
The plugin SHALL ship integrations with other plugins as separate modules under `agentdiff.integrations`. They SHALL be loaded only when the host requires them, SHALL NOT require the other plugin until the host calls them, and the core plugin SHALL work the same whether or not any integration is used.

#### Scenario: Not loaded by default
- **WHEN** the host calls `setup()` and never requires an integration module
- **THEN** no `agentdiff.integrations.*` module is loaded and neither neo-tree, oil nor grug-far is required

#### Scenario: Other plugin absent
- **WHEN** the host requires an integration module while the plugin it integrates with is not installed
- **THEN** requiring the module succeeds and agentdiff keeps working

### Requirement: Neo-tree integration
`agentdiff.integrations.neotree` SHALL provide a neo-tree component that shows a review mark (with the `AgentdiffTreeFile` / `AgentdiffTreeDir` highlights) on files with pending changes and on collapsed directories containing one, a function returning neo-tree's default renderers with that component added next to `git_status`, and a setup helper that refreshes the tree when pending changes change.

#### Scenario: Component marks a changed file
- **WHEN** a file has pending changes and neo-tree renders it with the component
- **THEN** the component returns the review icon with the `AgentdiffTreeFile` highlight, and nothing for files without pending changes

#### Scenario: Expanded directory
- **WHEN** a directory contains a changed file and is expanded in neo-tree
- **THEN** the component shows no mark on the directory

### Requirement: Oil integration
`agentdiff.integrations.oil` SHALL provide a setup helper that claims, before and after, every path touched by oil.nvim's file actions (create, delete, move, copy), so they are never shown as agent changes.

#### Scenario: Rename in oil
- **WHEN** the oil integration is set up and the user renames a file in oil
- **THEN** neither the old nor the new path is shown as a pending change

### Requirement: grug-far integration
`agentdiff.integrations.grug_far` SHALL provide an `on_before_edit_file` hook for grug-far that claims each file right before grug-far rewrites it and then lets grug-far continue.

#### Scenario: Project-wide replace
- **WHEN** grug-far runs a replacement with the hook configured
- **THEN** every replaced file is claimed, grug-far's edit proceeds, and none of the files is shown as a pending change
