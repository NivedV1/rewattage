/* history-dialog.vala
 *
 * Copyright 2025 v81d
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using DBusInterface;
using DeviceManager;
using Gee;
using NumericToolkit;

namespace Wattage {
  internal class HistoryDialog : Adw.Dialog {
    private const uint MIN_MINUTES = 5;
    private const uint MAX_MINUTES = 90 * 24 * 60;
    private const uint MAX_RESOLUTION = 720;
    private const int LIVE_REFRESH_INTERVAL = 60;
    private const uint[] PRESETS = {60, 360, 1440, 10080, 43200};

    private DeviceObject device;
    private Settings settings;
    private string power_unit;

    private HistoryChart percentage;
    private HistoryChart rate;
    private Gtk.MenuButton range_options;
    private Adw.SpinRow timespan;
    private Adw.SpinRow resolution;
    private Gtk.ToggleButton[] range_buttons;

    private Cancellable? request;
    private uint debounce_id;
    private uint pending_charts;
    private int64 last_load;

    public signal void refresh_requested ();

    public HistoryDialog (DeviceObject device, Settings settings, string power_unit) {
      Object (title: _("Device History"), content_width: 736, content_height: 540);

      this.device = device;
      this.settings = settings;
      this.power_unit = power_unit;

      var header = new Adw.HeaderBar () {
        title_widget = new Adw.WindowTitle (this.title, device.model ?? device.native_path ?? "")
      };
      var refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
        tooltip_text = _("Refresh")
      };
      refresh.clicked.connect (this.on_refresh_clicked);
      header.pack_start (refresh);

      var toolbar = new Adw.ToolbarView ();
      toolbar.add_top_bar (header);
      this.child = toolbar;

      var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 13) {
        margin_start = 18, margin_end = 18, margin_top = 11, margin_bottom = 18
      };
      content.append (this.build_range_controls ());

      this.percentage = new HistoryChart (HistoryMetric.PERCENTAGE,
        _("Current Charge Percentage"), "%", Adw.AccentColor.BLUE);
      this.rate = new HistoryChart (HistoryMetric.RATE,
        _("Net Energy Rate"), power_unit, Adw.AccentColor.TEAL);
      content.append (this.percentage);
      content.append (this.rate);

      var clamp = new Adw.Clamp () {
        maximum_size = 680, tightening_threshold = 475, child = content
      };
      var scroll = new Gtk.ScrolledWindow () {
        hscrollbar_policy = Gtk.PolicyType.NEVER, child = clamp
      };
      toolbar.content = scroll;

      this.closed.connect (this.cancel_load);
      this.load_history (true);
    }

    private Gtk.Widget build_range_controls () {
      var controls = new Adw.WrapBox () {
        child_spacing = 6, line_spacing = 6, justify = Adw.JustifyMode.FILL,
        justify_last_line = true
      };

      string[] labels = {"1 h", "6 h", "24 h", "7 d", "30 d"};
      this.range_buttons = new Gtk.ToggleButton[PRESETS.length];
      for (int i = 0; i < PRESETS.length; i++) {
        var button = new Gtk.ToggleButton.with_label (labels[i]);
        button.clicked.connect (this.select_preset);
        this.range_buttons[i] = button;
        controls.append (button);
      }

      this.timespan = new Adw.SpinRow.with_range (MIN_MINUTES, MAX_MINUTES, 1) {
        title = _("Timespan"),
        numeric = true
      };
      var minutes = new Gtk.Label ("min");
      minutes.add_css_class ("dim-label");
      this.timespan.add_suffix (minutes);
      this.timespan.value = this.settings.get_uint ("history-timespan")
        .clamp (MIN_MINUTES, MAX_MINUTES);

      this.resolution = new Adw.SpinRow.with_range (1, MAX_RESOLUTION, 1) {
        title = _("Resolution"),
        subtitle = _("The approximate number of history points to return."),
        numeric = true
      };
      this.resolution.value = this.settings.get_uint ("history-resolution").clamp (1, MAX_RESOLUTION);

      var options = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
      options.add_css_class ("boxed-list");
      options.append (this.timespan);
      options.append (this.resolution);
      this.range_options = new Gtk.MenuButton () {
        icon_name = "preferences-system-symbolic",
        tooltip_text = _("Timespan"),
        popover = new Gtk.Popover () { child = options }
      };
      controls.append (this.range_options);

      this.update_range_buttons ();
      this.timespan.notify["value"].connect (this.on_range_changed);
      this.resolution.notify["value"].connect (this.on_range_changed);
      return controls;
    }

    private void select_preset (Gtk.Button button) {
      for (int i = 0; i < this.range_buttons.length; i++) {
        if (this.range_buttons[i] == button) {
          this.timespan.value = PRESETS[i];
          this.update_range_buttons ();
          break;
        }
      }
    }

    private void update_range_buttons () {
      uint selected = (uint) this.timespan.value;
      bool is_preset = false;
      for (int i = 0; i < this.range_buttons.length; i++) {
        bool active = selected == PRESETS[i];
        this.range_buttons[i].active = active;
        is_preset |= active;
      }
      if (is_preset)
        this.range_options.icon_name = "preferences-system-symbolic";
      else
        this.range_options.label = "%u min".printf (selected);
    }

    private void on_range_changed () {
      this.update_range_buttons ();
      this.settings.set_uint ("history-timespan", (uint) this.timespan.value);
      this.settings.set_uint ("history-resolution", (uint) this.resolution.value);
      this.cancel_load ();
      this.percentage.show_loading ();
      this.rate.show_loading ();

      this.debounce_id = Timeout.add (220, () => {
        this.debounce_id = 0;
        this.load_history (false);
        return Source.REMOVE;
      });
    }

    public void update_device (DeviceObject device) {
      if (device.object_path != this.device.object_path ||
        device.vendor != this.device.vendor ||
        device.model != this.device.model ||
        device.serial != this.device.serial)
        return;

      this.device = device;
      if (this.debounce_id == 0 && this.request == null &&
        get_monotonic_time () - this.last_load >= LIVE_REFRESH_INTERVAL * TimeSpan.SECOND) {
        this.load_history (false);
      }
    }

    private void on_refresh_clicked () {
      this.refresh_requested ();
      this.load_history (true);
    }

    private void cancel_load () {
      if (this.debounce_id != 0) {
        Source.remove (this.debounce_id);
        this.debounce_id = 0;
      }
      this.request?.cancel ();
      this.request = null;
      this.pending_charts = 0;
    }

    private void load_history (bool show_loading) {
      this.cancel_load ();
      this.last_load = get_monotonic_time ();

      uint seconds = (uint) this.timespan.value * 60;
      uint resolution = (uint) this.resolution.value;
      int64 end = get_real_time () / TimeSpan.SECOND;
      int64 start = end - seconds;

      if (!this.device.has_history) {
        this.percentage.show_unavailable ();
        this.rate.show_unavailable ();
        return;
      }

      if (show_loading) {
        this.percentage.show_loading ();
        this.rate.show_loading ();
      }
      var request = new Cancellable ();
      this.request = request;
      this.pending_charts = 2;
      this.load_series.begin (this.device.upower_proxy, this.percentage, "charge",
        start, end, resolution, request);
      this.load_series.begin (this.device.upower_proxy, this.rate, "rate",
        start, end, resolution, request);
    }

    private async void load_series (UPower.Device proxy, HistoryChart chart, string type,
      int64 start, int64 end, uint resolution, Cancellable request) {
      try {
        var readings = yield proxy.get_history (type, (uint) (end - start), resolution, request);
        if (request.is_cancelled ())
          return;

        var sorted = new ArrayList<UPower.HistoryItem?> ();
        foreach (var reading in readings)
          sorted.add (reading);
        sorted.sort ((a, b) => (a.time > b.time ? 1 : 0) - (a.time < b.time ? 1 : 0));

        var points = new ArrayList<HistoryPoint?> ();
        bool starts_segment = true;
        foreach (UPower.HistoryItem reading in sorted) {
          if (reading.time < start || reading.time > end)
            continue;

          bool percentage = type == "charge";
          // Unknown-state readings mark breaks in UPower history.
          if (reading.state == 0 || !reading.value.is_finite () ||
            (percentage && (reading.value < 0 || reading.value > 100))) {
            starts_segment = true;
            continue;
          }

          double value = reading.value;
          if (!percentage) {
            value = si_convert (value, this.power_unit);
            if (reading.state == 2)
              value = -value.abs ();
          }
          if (value.is_finite ()) {
            points.add (HistoryPoint (reading.time, value, reading.state, starts_segment));
            starts_segment = false;
          }
        }
        chart.show_series (points, start, end);
      } catch (Error e) {
        if (request.is_cancelled ())
          return;

        warning ("Error getting device history: %s", e.message);
        chart.show_unavailable ();
      }

      if (--this.pending_charts == 0)
        this.request = null;
    }
  }
}
