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

  /* ---------------------------------------------------------------------
   * "Map is actually ready" signal for the overlay map. app.R's
   * output$map has no tracked reactive dependencies, so it renders
   * exactly once, for the life of the session -- a bare basemap (no
   * bounds/layers) that doesn't wait on the live GTFS/TDM data. The real
   * layers + fly-to-bounds are added via a proxy once that data is ready
   * (app.R's bootstrap observer), and every later update (filters, dark
   * mode) is also a proxy call -- the widget itself is never re-rendered.
   * But there's no guarantee the client has finished creating the
   * MapLibre map instance and registering mapgl's own proxy message
   * handler by the time that first data-ready proxy message is sent -- if
   * it arrives first, mapgl's handler silently drops it (no widget/map
   * found yet) with no error and no retry, permanently losing the layers.
   * Report back to Shiny once the map instance genuinely exists and has
   * fired its own 'load' event, so the R side can gate the bootstrap on
   * input$map_ready instead of racing it. Since this only ever needs to
   * happen once per session (output$map only ever fires "shiny:value"
   * once), a plain short poll is enough -- no need to reason about
   * stale/replaced widget references from a second render, because there
   * isn't one.
   * ------------------------------------------------------------------- */
  $(document).on("shiny:value", function (event) {
    if (!event.target || event.target.id !== "map") return;

    function waitForMap(attemptsLeft) {
      var widget = window.HTMLWidgets && HTMLWidgets.find && HTMLWidgets.find("#map");
      var map = widget && widget.getMap && widget.getMap();
      if (map) {
        watchContainerResize(event.target, map);
        var reported = false;
        var reportReady = function () {
          if (reported) return;
          reported = true;
          Shiny.setInputValue("map_ready", Date.now());
        };
        if (map.loaded()) {
          reportReady();
        } else {
          map.once("load", reportReady);
          // map may finish loading in the gap between the loaded() check
          // above and once("load", ...) actually registering -- once()
          // only catches *future* firings, so a load that already
          // happened in that gap would otherwise be missed forever.
          // Re-check once more and fire directly if that happened;
          // reportReady()'s `reported` guard makes it safe if both paths
          // end up firing.
          if (map.loaded()) reportReady();
        }
        // Reports every camera movement's completion (pan, zoom, and the
        // bootstrap observer's own fit_bounds() flight into the GTFS
        // network alike) so app.R can reveal the GTFS/TDM layers -- added
        // hidden -- only once that flight actually arrives, instead of
        // them popping into view (as an enormous, all-stops-in-one
        // cluster, since the camera is still at the zoomed-out initial
        // view when they'd otherwise be added) before the camera has
        // moved at all. Deliberately map.on(), not map.once(): app.R's own
        // observer guards against reacting to any *earlier* moveend with
        // req(map_bootstrapped()), so this can just report every
        // occurrence and let the server decide which one matters, rather
        // than this client-side code needing to know which specific
        // moveend is "the" one to wait for.
        map.on("moveend", function () {
          Shiny.setInputValue("map_moveend", Date.now());
        });
        return;
      }
      if (attemptsLeft > 0) {
        setTimeout(function () { waitForMap(attemptsLeft - 1); }, 100);
      }
    }
    waitForMap(50); // up to ~5s
  });

  /*
   * htmlwidgets.js only calls a widget's resize() method in response to the
   * *window*'s resize event (see htmlwidgets.js: `on(window, "resize",
   * resizeHandler)`) -- it has no ResizeObserver on the widget's own
   * container element. This app's #map container is sized by bslib's flex
   * fill layout, which can still be settling (fonts loading, sidebar
   * measuring itself) a moment after first paint, with no window resize
   * event involved at all. MapLibre's <canvas> has explicit width/height
   * attributes set at creation time and never finds out the container
   * changed size unless map.resize() is called directly -- left alone this
   * shows up as an undersized/stretched map right after load, and a
   * fit_bounds() flyTo that appears to snap instead of animate because it's
   * animating relative to stale canvas dimensions.
   */
  function watchContainerResize(el, map) {
    if (el._mapglResizeObserver) el._mapglResizeObserver.disconnect();
    var ro = new ResizeObserver(function () {
      map.resize();
    });
    ro.observe(el);
    el._mapglResizeObserver = ro;
  }
})();
