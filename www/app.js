/*
 * Custom Shiny input bindings for this app's sidebar controls -- real
 * components, not CSS reskins of radioButtons()/checkboxGroupInput().
 * Markup is produced server-side by R/custom_inputs.R (segmented_input(),
 * chip_group_input()); this file only wires up interaction. Both bindings
 * read their *initial* value straight from whatever the server marked
 * active in the rendered HTML (aria-checked / is-active), so there is no
 * JS-computed default -- getValue() is correct from the very first call,
 * before any click, which is what keeps every req(input$...) downstream
 * from starving on page load.
 */

(function () {
  "use strict";

  /* ---------------------------------------------------------------------
   * Segmented control: single-select, radiogroup semantics, a sliding
   * indicator pill behind the active option.
   * ------------------------------------------------------------------- */
  var SegmentedInputBinding = new Shiny.InputBinding();

  $.extend(SegmentedInputBinding, {
    find: function (scope) {
      return $(scope).find('[data-shiny-input-type="segmented"]');
    },

    getValue: function (el) {
      var active = el.querySelector('.segmented-option.is-active');
      return active ? active.getAttribute("data-value") : null;
    },

    setValue: function (el, value) {
      this._activate(el, el.querySelector('.segmented-option[data-value="' + value + '"]'));
    },

    // Move the active state to `option` (a .segmented-option button) and
    // reposition the sliding indicator to match its box.
    _activate: function (el, option) {
      if (!option) return;
      var options = el.querySelectorAll(".segmented-option");
      options.forEach(function (o) {
        var isActive = o === option;
        o.classList.toggle("is-active", isActive);
        o.setAttribute("aria-checked", isActive ? "true" : "false");
        o.tabIndex = isActive ? 0 : -1;
      });
      this._positionIndicator(el, option);
    },

    _positionIndicator: function (el, option) {
      var indicator = el.querySelector(".segmented-indicator");
      if (!indicator || !option) return;
      indicator.style.width = option.offsetWidth + "px";
      indicator.style.transform = "translateX(" + option.offsetLeft + "px)";
    },

    subscribe: function (el, callback) {
      var self = this;

      $(el).on("click.segmentedInputBinding", ".segmented-option", function () {
        self._activate(el, this);
        callback(true);
      });

      $(el).on("keydown.segmentedInputBinding", ".segmented-option", function (e) {
        var options = Array.prototype.slice.call(el.querySelectorAll(".segmented-option"));
        var idx = options.indexOf(this);
        var next = null;
        if (e.key === "ArrowRight" || e.key === "ArrowDown") next = options[(idx + 1) % options.length];
        else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = options[(idx - 1 + options.length) % options.length];
        else if (e.key === "Home") next = options[0];
        else if (e.key === "End") next = options[options.length - 1];
        if (next) {
          e.preventDefault();
          self._activate(el, next);
          next.focus();
          callback(true);
        }
      });

      // Sidebar has a real collapse/expand toggle -- if the container's
      // width changes, the indicator's pixel geometry needs recomputing
      // for whichever option is currently active.
      var ro = new ResizeObserver(function () {
        self._positionIndicator(el, el.querySelector(".segmented-option.is-active"));
      });
      ro.observe(el);
      el._segmentedResizeObserver = ro;
    },

    unsubscribe: function (el) {
      $(el).off(".segmentedInputBinding");
      if (el._segmentedResizeObserver) el._segmentedResizeObserver.disconnect();
    },

    initialize: function (el) {
      // Indicator starts hidden (no transition) until the first layout
      // pass has real geometry to animate from, so it doesn't sweep in
      // from the top-left corner on page load.
      this._positionIndicator(el, el.querySelector(".segmented-option.is-active"));
      requestAnimationFrame(function () { el.classList.add("segmented-ready"); });
    },

    getRatePolicy: function () {
      return { policy: "immediate" };
    }
  });

  Shiny.inputBindings.register(SegmentedInputBinding, "app.segmentedInput");

  /* ---------------------------------------------------------------------
   * Chip group: multi-select, group of independently-toggleable checkbox
   * chips. Real <button> elements, so Enter/Space activation is native --
   * no extra keyboard handling needed beyond click.
   * ------------------------------------------------------------------- */
  var ChipGroupInputBinding = new Shiny.InputBinding();

  $.extend(ChipGroupInputBinding, {
    find: function (scope) {
      return $(scope).find('[data-shiny-input-type="chipgroup"]');
    },

    getValue: function (el) {
      return Array.prototype.map.call(
        el.querySelectorAll('.chip-option.is-active'),
        function (o) { return o.getAttribute("data-value"); }
      );
    },

    setValue: function (el, values) {
      values = values || [];
      el.querySelectorAll(".chip-option").forEach(function (o) {
        var active = values.indexOf(o.getAttribute("data-value")) !== -1;
        o.classList.toggle("is-active", active);
        o.setAttribute("aria-checked", active ? "true" : "false");
      });
    },

    subscribe: function (el, callback) {
      $(el).on("click.chipGroupInputBinding", ".chip-option", function () {
        var active = !this.classList.contains("is-active");
        this.classList.toggle("is-active", active);
        this.setAttribute("aria-checked", active ? "true" : "false");
        callback(true);
      });
    },

    unsubscribe: function (el) {
      $(el).off(".chipGroupInputBinding");
    },

    getRatePolicy: function () {
      return { policy: "immediate" };
    }
  });

  Shiny.inputBindings.register(ChipGroupInputBinding, "app.chipGroupInput");
})();
