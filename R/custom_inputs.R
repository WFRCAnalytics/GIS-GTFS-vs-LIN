# R-side constructors for the custom Shiny.InputBinding components in
# www/app.js (SegmentedInputBinding / ChipGroupInputBinding). Markup contract
# with that file: a container carrying data-shiny-input-type, whose initial
# active option(s) are marked in the rendered HTML (is-active class +
# aria-checked) -- the JS binding reads that straight off the DOM, so the
# correct default value is available before any user interaction, no
# JS-side default-computation involved. Requires R/icons.R to be sourced
# first (chip_group_input()'s optional icons use brand_icon(), which now
# resolves through Font Awesome).

# Single-select segmented control -- drop-in replacement for
# radioButtons(inline = FALSE) in terms of value contract: `choices` is the
# same named-vector convention (names = labels, values = the strings that
# land in input[[inputId]]), and the reactive value is a single character
# string, exactly like radioButtons().
segmented_input <- function(inputId, choices, selected, label = NULL) {
  options <- Map(function(name, value) {
    active <- identical(value, selected)
    tags$button(
      type = "button", class = paste("segmented-option", if (active) "is-active"),
      `data-value` = value, role = "radio",
      `aria-checked` = if (active) "true" else "false",
      tabindex = if (active) "0" else "-1",
      name
    )
  }, names(choices), unname(choices))

  div(
    id = inputId, class = "segmented", `data-shiny-input-type` = "segmented",
    role = "radiogroup", `aria-label` = label %||% inputId,
    span(class = "segmented-indicator"),
    options
  )
}

# Multi-select chip toggle group -- drop-in replacement for
# checkboxGroupInput(inline = TRUE): `choices` is the same named-vector
# convention, and the reactive value is a character vector of the checked
# values, exactly like checkboxGroupInput(). `icons` is an optional named
# list (value -> brand_icon() name) for a leading glyph per chip.
chip_group_input <- function(inputId, choices, selected, icons = NULL, label = NULL) {
  chips <- Map(function(name, value) {
    active <- value %in% selected
    tags$button(
      type = "button", class = paste("chip-option", if (active) "is-active"),
      `data-value` = value, role = "checkbox",
      `aria-checked` = if (active) "true" else "false",
      if (!is.null(icons[[value]])) brand_icon(icons[[value]]),
      span(name)
    )
  }, names(choices), unname(choices))

  div(
    id = inputId, class = "chip-group", `data-shiny-input-type` = "chipgroup",
    role = "group", `aria-label` = label %||% inputId,
    chips
  )
}
